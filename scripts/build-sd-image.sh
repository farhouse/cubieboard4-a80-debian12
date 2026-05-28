#!/usr/bin/env bash
set -euo pipefail

SELF="$(basename "$0")"

RELEASE_BASE="https://github.com/farhouse/cubieboard4-a80-debian12/releases/download/external-images-2026-05"
RAW_BASE="https://raw.githubusercontent.com/farhouse/cubieboard4-a80-debian12/main"
WORK_DIR="build/sd-image"
OUTPUT=""
DTS_SRC="dts/sun9i-a80-cubieboard4.dts"
DTS_ASSET="dts/sun9i-a80-cubieboard4.dts"
DTS_SHA256="81767357cadd17b0980d4f6787508216740831b89e76588421be56f40d402a0f"
DTB="dtb/sun9i-a80-cubieboard4.dtb"
WIFI_PKGS="iw wpasupplicant isc-dhcp-client"
EXTRA_PKGS="parted"
FIRMWARE_DIR=""
WITH_FIRMWARE=1
DOWNLOAD=1
WIZARD=0
WITH_INSTALLER=1
WITH_WIFI_WIZARD=1
WITH_EXTRAS=0
WRITE_SD=0
SD_DEVICE=""
CUSTOM_DTB=0

BOOT_ASSET="boot-cubieboard4.bin.gz"
ROOTFS_ASSET="debian-bookworm-armhf-vim3ve.bin.gz"
VENDOR_SD_ASSET="cb4-debian-server-hdmi-card-v1.0.img.7z"
UBOOT_FIX_ASSET="u-boot-sunxi-with-spl.bin"

BOOT_SHA256="768d66822c61534083330951a4c6ce21493a892596f5a1fb86bef692ccda1411"
ROOTFS_SHA256="f9bc8b5e61599d4a680eca63ddd09dcde5392ba5161325e1031eef9b574adffb"
VENDOR_SD_SHA256="8af6f75dffa4b215fa40e254365f54de89510a2c0934b5ab4ac61e441eada3f5"
UBOOT_FIX_SHA256="56e1ce91b886be77673d9c27278a8ddf71775052085bc4b18583368a899e1f5d"

CACHE_DIR=""
ROOT_MOUNT=""
VENDOR_MOUNT=""
IMAGE_LOOP=""
VENDOR_LOOP=""

# ── Colors (only for wizard) ──────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────
log()   { printf '%s\n' "$*"; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
step()  { printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}%s${NC}\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠ %s${NC}\n" "$*"; }
ok()    { printf "  ${GREEN}✔ %s${NC}\n" "$*"; }
sep()   { printf "  ${CYAN}────────────────────────────────────────────${NC}\n"; }

usage() {
	cat <<EOF
Usage:
  sudo $SELF [--output FILE] [--work-dir DIR] [--interactive]

Builds a Cubieboard4 Debian 12 SD image from preserved release assets, then
patches the root filesystem with the validated DTB and AP6330 WiFi firmware.

Default assets:
  release: $RELEASE_BASE
  boot:    $BOOT_ASSET
  rootfs:  $ROOTFS_ASSET
  vendor:  $VENDOR_SD_ASSET
  uboot:   $UBOOT_FIX_ASSET (fixed eMMC clock register)

DTB is compiled from $DTS_SRC during the build.

Options:
  --output FILE        Final image path.
                       Default: WORK_DIR/cubieboard4-a80-debian12-sd.img
  --work-dir DIR       Cache and temporary files, default: $WORK_DIR.
  --release-base URL   Override the GitHub Release download base URL.
  --dtb FILE           DTB to install (overrides compilation from $DTS_SRC).
  --firmware-dir DIR   Use AP6330 firmware from DIR instead of vendor image.
                       Expected files: fw_bcm40183b2_ag.bin, nvram_ap6330.txt
  --no-firmware        Do not install AP6330 WiFi firmware.
  --no-installer       Do not copy install-to-emmc.sh into /root.
  --no-wifi-wizard     Do not copy wifi-wizard.sh into /root.
  --with-extras        Install convenience packages in the armhf rootfs:
                       $EXTRA_PKGS
  --no-extras          Do not install convenience packages (default in CLI mode).
  --write-sd           Ask for a target block device and write the final image.
  --sd-device DEV      Target block device for --write-sd, e.g. /dev/sdb.
  --skip-download      Reuse already cached assets only.
  -i, --interactive    Interactive wizard mode with image profiles and choices.
  -h, --help           Show this help.

Requirements:
  Linux root shell with curl or wget, sha256sum, gzip, dtc (device-tree-compiler),
  blkid, losetup, mount, umount, and mkimage from u-boot-tools. 7z is also required
  unless --firmware-dir or --no-firmware is used.

  If WiFi firmware or --with-extras is enabled, qemu-arm-static is needed to
  install packages inside the armhf rootfs. The script can install qemu-user-static
  for you in interactive mode.
EOF
}

require_cmd() {
	local cmd="$1"
	local pkg="${2:-}"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		if [ -n "$pkg" ]; then
			log "Missing: $cmd (package: $pkg)"
			missing_pkgs="$missing_pkgs $pkg"
		else
			die "required command not found: $cmd"
		fi
	fi
}

cleanup() {
	set +e
	if [ -n "$ROOT_MOUNT" ]; then
		for bind_mount in "$ROOT_MOUNT/dev/pts" "$ROOT_MOUNT/sys" "$ROOT_MOUNT/dev" "$ROOT_MOUNT/proc"; do
			if mountpoint -q "$bind_mount"; then
				umount "$bind_mount"
			fi
		done
	fi
	if [ -n "$ROOT_MOUNT" ] && mountpoint -q "$ROOT_MOUNT"; then
		umount "$ROOT_MOUNT"
	fi
	if [ -n "$VENDOR_MOUNT" ] && mountpoint -q "$VENDOR_MOUNT"; then
		umount "$VENDOR_MOUNT"
	fi
	if [ -n "$IMAGE_LOOP" ]; then
		losetup -d "$IMAGE_LOOP" >/dev/null 2>&1
	fi
	if [ -n "$VENDOR_LOOP" ]; then
		losetup -d "$VENDOR_LOOP" >/dev/null 2>&1
	fi
}

download_asset() {
	local asset="$1"
	local dest="$CACHE_DIR/$asset"
	local url="$RELEASE_BASE/$asset"

	if [ -f "$dest" ]; then
		log "Using cached asset: $dest"
		return
	fi

	[ "$DOWNLOAD" -eq 1 ] || die "missing cached asset and --skip-download was used: $dest"

	log "Downloading: $url"
	mkdir -p "$(dirname "$dest")"
	if command -v curl >/dev/null 2>&1; then
		curl -L --connect-timeout 15 --max-time 120 --fail --output "$dest.tmp" "$url" || {
			log "curl failed with exit code $?"
			die "curl failed — check network / URL: $url"
		}
	elif command -v wget >/dev/null 2>&1; then
		wget --timeout=15 -O "$dest.tmp" "$url" || {
			log "wget failed with exit code $?"
			die "wget failed — check network / URL: $url"
		}
	else
		die "required command not found: curl or wget"
	fi
	mv "$dest.tmp" "$dest"
}

verify_sha256() {
	local file="$1"
	local expected="$2"
	log "Verifying SHA256: $file"
	printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
}

attach_loop() {
	local image="$1"
	local loopdev
	loopdev="$(losetup --find --partscan --show "$image")"
	if command -v udevadm >/dev/null 2>&1; then
		udevadm settle
	fi
	printf '%s\n' "$loopdev"
}

partition_path() {
	local loopdev="$1"
	local partno="$2"
	if [ -b "${loopdev}p${partno}" ]; then
		printf '%s\n' "${loopdev}p${partno}"
	elif [ -b "${loopdev}${partno}" ]; then
		printf '%s\n' "${loopdev}${partno}"
	else
		die "partition ${partno} not found for loop device: $loopdev"
	fi
}

copy_ap6330_firmware() {
	local src_dir="$1"
	local target="$2/lib/firmware/brcm"
	local fw_bin="$src_dir/fw_bcm40183b2_ag.bin"
	local fw_txt="$src_dir/nvram_ap6330.txt"
	[ -f "$fw_bin" ] || die "missing AP6330 firmware: $fw_bin"
	[ -f "$fw_txt" ] || die "missing AP6330 NVRAM: $fw_txt"
	log "Installing AP6330 WiFi firmware"
	install -d "$target"
	install -m 0644 "$fw_bin" "$target/brcmfmac4330-sdio.bin"
	install -m 0644 "$fw_txt" "$target/brcmfmac4330-sdio.txt"
}

detect_kernel_version() {
	local boot_dir="$1/boot"
	local kernel="" path
	for path in "$boot_dir"/vmlinuz-*; do
		[ -f "$path" ] || continue
		kernel="$(basename "$path")"
	done
	[ -n "$kernel" ] || die "could not find kernel image in: $boot_dir"
	printf '%s\n' "${kernel#vmlinuz-}"
}

write_sd_boot_script() {
	local root_part="$1"
	local root_mount="$2"
	local root_uuid kernel_version boot_cmd="$root_mount/boot/boot.cmd"
	root_uuid="$(blkid -s UUID -o value "$root_part")"
	[ -n "$root_uuid" ] || die "could not determine rootfs UUID for: $root_part"
	kernel_version="$(detect_kernel_version "$root_mount")"
	log "Writing SD boot script with root=UUID=$root_uuid"
	cat >"$boot_cmd" <<EOF
setenv devtype mmc
load \${devtype} \${devnum}:\${distro_bootpart} \${kernel_addr_r} /boot/vmlinuz-${kernel_version}
load \${devtype} \${devnum}:\${distro_bootpart} \${ramdisk_addr_r} /boot/initrd.img-${kernel_version}
setenv ramdisk_size \${filesize}
setenv bootargs root=UUID=${root_uuid} rw rootwait
load \${devtype} \${devnum}:\${distro_bootpart} \${fdt_addr_r} /boot/sun9i-a80-cubieboard4.dtb
bootz \${kernel_addr_r} \${ramdisk_addr_r}:\${ramdisk_size} \${fdt_addr_r}
EOF
	mkimage -C none -A arm -T script -d "$boot_cmd" "$root_mount/boot/boot.scr"
}

validate_output_path() {
	case "$OUTPUT" in /dev/*) die "--output must be an image file path, not a block device: $OUTPUT" ;; esac
	[ ! -b "$OUTPUT" ] || die "--output points to a block device: $OUTPUT"
	[ ! -d "$OUTPUT" ] || die "--output points to a directory: $OUTPUT"
	[ ! -L "$OUTPUT" ] || die "--output must not be a symlink: $OUTPUT"
	if [ -e "$OUTPUT" ] && [ ! -f "$OUTPUT" ]; then
		die "--output exists but is not a regular file: $OUTPUT"
	fi
}

list_write_targets() {
	local root_source="" root_disk="" root_pk=""
	root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
	if [ -n "$root_source" ]; then
		root_pk="$(lsblk -n -o PKNAME "$root_source" 2>/dev/null | head -1 || true)"
		[ -n "$root_pk" ] && root_disk="/dev/$root_pk"
	fi

	log "Available block devices:"
	if [ -n "$root_disk" ]; then
		log "  root disk excluded: $root_disk"
	fi
	lsblk -dpno NAME,SIZE,TRAN,RM,MODEL | while read -r line; do
		case "$line" in
			"$root_disk "*) continue ;;
		esac
		printf '  %s\n' "$line"
	done
}

choose_sd_device() {
	local dev
	list_write_targets
	log ""
	log "Enter the target device path for the microSD (e.g. /dev/sdb)."
	log "Leave empty to build the image only."
	printf "  ${BOLD}> ${NC}"
	read -r dev </dev/tty
	if [ -z "$dev" ]; then
		WRITE_SD=0
		SD_DEVICE=""
		return 0
	fi
	[ -b "$dev" ] || die "not a block device: $dev"
	WRITE_SD=1
	SD_DEVICE="$dev"
}

extract_vendor_firmware() {
	local archive="$CACHE_DIR/$VENDOR_SD_ASSET"
	local extract_dir="$WORK_DIR/vendor-sd"
	local vendor_img="$extract_dir/cb4-debian-server-hdmi-card-v1.0.img"
	local vendor_root
	require_cmd 7z
	download_asset "$VENDOR_SD_ASSET"
	verify_sha256 "$archive" "$VENDOR_SD_SHA256"
	if [ ! -f "$vendor_img" ]; then
		log "Extracting vendor SD image"
		mkdir -p "$extract_dir"
		7z x -y "-o$extract_dir" "$archive"
	fi
	[ -f "$vendor_img" ] || die "vendor image not found after extraction: $vendor_img"
	VENDOR_MOUNT="$WORK_DIR/mnt-vendor"
	mkdir -p "$VENDOR_MOUNT"
	VENDOR_LOOP="$(attach_loop "$vendor_img")"
	vendor_root="$(partition_path "$VENDOR_LOOP" 2)"
	log "Mounting vendor rootfs: $vendor_root"
	mount -o ro "$vendor_root" "$VENDOR_MOUNT"
	copy_ap6330_firmware "$VENDOR_MOUNT/lib/firmware/ap6330" "$ROOT_MOUNT"
}

download_dts_if_missing() {
	if [ -f "$DTS_SRC" ]; then return 0; fi
	if [ -f "$CACHE_DIR/$DTS_ASSET" ]; then
		DTS_SRC="$CACHE_DIR/$DTS_ASSET"
		return 0
	fi
	dts_url="$RAW_BASE/$DTS_ASSET"
	dts_dest="$CACHE_DIR/$DTS_ASSET"
	dts_tmp="${dts_dest}.tmp-$$"
	mkdir -p "$(dirname "$dts_dest")"
	log "Downloading DTS: $dts_url"
	if command -v curl >/dev/null 2>&1; then
		curl -L --connect-timeout 15 --max-time 60 --fail --output "$dts_tmp" "$dts_url" || {
			rc_curl=$?; log "curl exit code: $rc_curl"
			die "curl failed (exit $rc_curl) — check network / URL: $dts_url"
		}
	elif command -v wget >/dev/null 2>&1; then
		wget --timeout=15 -O "$dts_tmp" "$dts_url" || {
			rc_wget=$?; die "wget failed (exit $rc_wget) — check network / URL: $dts_url"
		}
	else
		die "required command not found: curl or wget"
	fi
	mv "$dts_tmp" "$dts_dest"
	DTS_SRC="$dts_dest"
}

# ── Wizard ─────────────────────────────────────────────────────
bool_word() {
	if [ "$1" -eq 1 ]; then
		printf "${GREEN}yes${NC}"
	else
		printf "${RED}no${NC}"
	fi
}

ask_yn() {
	local prompt="$1"
	local default="${2:-y}"
	local reply suffix
	if [ "$default" = "y" ]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
	printf "  ${BOLD}%s %s ${NC}" "$prompt" "$suffix"
	read -r reply </dev/tty
	case "$reply" in
		[yY]*) return 0 ;;
		[nN]*) return 1 ;;
		*) [ "$default" = "y" ] ;;
	esac
}

wizard_asset_status() {
	printf "\n  ${BOLD}Cached assets:${NC}\n"
	for pair in \
		"$BOOT_ASSET:boot image" \
		"$ROOTFS_ASSET:Debian rootfs" \
		"$UBOOT_FIX_ASSET:fixed U-Boot"; do
		local file="${pair%%:*}"
		local label="${pair#*:}"
		if [ -f "$CACHE_DIR/$file" ]; then
			printf "  ${GREEN}ok${NC}   %s\n" "$label"
		else
			printf "  ${YELLOW}miss${NC} %s\n" "$label"
		fi
	done
	if [ -n "$FIRMWARE_DIR" ]; then
		printf "  ${GREEN}ok${NC}   firmware dir: %s\n" "$FIRMWARE_DIR"
	elif [ -f "$CACHE_DIR/$VENDOR_SD_ASSET" ]; then
		printf "  ${GREEN}ok${NC}   vendor SD firmware source\n"
	else
		printf "  ${YELLOW}miss${NC} vendor SD firmware source\n"
	fi
	if [ "$CUSTOM_DTB" -eq 1 ]; then
		printf "  ${GREEN}ok${NC}   custom DTB: %s\n" "$DTB"
	elif [ -f "$DTS_SRC" ] || [ -f "$CACHE_DIR/$DTS_ASSET" ]; then
		printf "  ${GREEN}ok${NC}   DTS source\n"
	else
		printf "  ${YELLOW}miss${NC} DTS source\n"
	fi
}

wizard_summary() {
	local img
	[ -n "$OUTPUT" ] && img="$OUTPUT" || img="$WORK_DIR/cubieboard4-a80-debian12-sd.img"
	printf "\n  ${BOLD}Selected build:${NC}\n"
	printf "  Work dir:          %s\n" "$WORK_DIR"
	printf "  Output image:      %s\n" "$img"
	printf "  Download missing:  %b\n" "$(bool_word "$DOWNLOAD")"
	if [ "$CUSTOM_DTB" -eq 1 ]; then
		printf "  DTB:               custom file: %s\n" "$DTB"
	else
		printf "  DTB:               compile from %s\n" "$DTS_SRC"
	fi
	printf "  Fixed U-Boot:      always installed\n"
	printf "  AP6330 firmware:   %b\n" "$(bool_word "$WITH_FIRMWARE")"
	printf "  install-to-emmc:   %b\n" "$(bool_word "$WITH_INSTALLER")"
	printf "  wifi-wizard:       %b\n" "$(bool_word "$WITH_WIFI_WIZARD")"
	if [ "$WITH_FIRMWARE" -eq 1 ] || [ "$WITH_WIFI_WIZARD" -eq 1 ]; then
		printf "  WiFi packages:     %s\n" "$WIFI_PKGS"
	fi
	printf "  Extra packages:    %b\n" "$(bool_word "$WITH_EXTRAS")"
	printf "  Write to SD:       %b\n" "$(bool_word "$WRITE_SD")"
	if [ "$WRITE_SD" -eq 1 ]; then
		printf "  SD target:         %s\n" "$SD_DEVICE"
	fi
}

wizard_custom_options() {
	if ask_yn "Download missing release assets?" "y"; then DOWNLOAD=1; else DOWNLOAD=0; fi
	if ask_yn "Install AP6330 WiFi firmware?" "y"; then WITH_FIRMWARE=1; else WITH_FIRMWARE=0; fi
	if [ "$WITH_FIRMWARE" -eq 1 ]; then
		if ask_yn "Use an already extracted firmware directory?" "n"; then
			printf "  ${BOLD}Firmware directory: ${NC}"
			read -r FIRMWARE_DIR </dev/tty
			[ -d "$FIRMWARE_DIR" ] || die "firmware directory not found: $FIRMWARE_DIR"
		fi
		if ask_yn "Copy wifi-wizard.sh to /root?" "y"; then WITH_WIFI_WIZARD=1; else WITH_WIFI_WIZARD=0; fi
	else
		WITH_WIFI_WIZARD=0
	fi
	if ask_yn "Copy install-to-emmc.sh to /root?" "y"; then WITH_INSTALLER=1; else WITH_INSTALLER=0; fi
	if ask_yn "Install convenience packages in the armhf rootfs?" "n"; then WITH_EXTRAS=1; else WITH_EXTRAS=0; fi
	if ask_yn "Write the image to a microSD after building?" "n"; then
		choose_sd_device
	else
		WRITE_SD=0
		SD_DEVICE=""
	fi
}

wizard() {
	local choice
	printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	printf "\n${BOLD}  Cubieboard4 A80 SD Image Builder${NC}"
	printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

	wizard_asset_status
	printf "\n  ${BOLD}Paths:${NC}\n"
	printf "  Work dir: %s\n" "$WORK_DIR"
	if [ -n "$OUTPUT" ]; then
		printf "  Output:   %s\n" "$OUTPUT"
	else
		printf "  Output:   %s\n" "$WORK_DIR/cubieboard4-a80-debian12-sd.img"
	fi

	printf "\n  ${BOLD}Choose an image profile:${NC}\n"
	printf "  1) Recommended  DTB + fixed U-Boot + WiFi firmware/tools + helper scripts\n"
	printf "  2) Field kit    Recommended + apt packages: %s\n" "$EXTRA_PKGS"
	printf "  3) Minimal      Bootable image only, no WiFi firmware or helper scripts\n"
	printf "  4) Custom       Choose each optional step\n"
	printf "  ${BOLD}> ${NC}"
	read -r choice </dev/tty
	[ -n "$choice" ] || choice=1

	case "$choice" in
		1)
			DOWNLOAD=1; WITH_FIRMWARE=1; WITH_WIFI_WIZARD=1
			WITH_INSTALLER=1; WITH_EXTRAS=0; WRITE_SD=0
			;;
		2)
			DOWNLOAD=1; WITH_FIRMWARE=1; WITH_WIFI_WIZARD=1
			WITH_INSTALLER=1; WITH_EXTRAS=1; WRITE_SD=0
			;;
		3)
			DOWNLOAD=1; WITH_FIRMWARE=0; WITH_WIFI_WIZARD=0
			WITH_INSTALLER=0; WITH_EXTRAS=0; WRITE_SD=0
			;;
		4)
			wizard_custom_options
			;;
		*)
			die "unknown profile: $choice"
			;;
	esac

	if [ "$choice" != "4" ]; then
		if ask_yn "Write the image to a microSD after building?" "n"; then
			choose_sd_device
		fi
	fi

	wizard_summary
	printf "\n"
	ask_yn "Proceed with this build?" "y" || die "aborted"
}

# ── Argument parsing ───────────────────────────────────────────
HAD_ARGS=$#
while [ "$#" -gt 0 ]; do
	case "$1" in
		--output)     [ "$#" -ge 2 ] || die "--output requires a value"; OUTPUT="$2"; shift 2 ;;
		--work-dir)   [ "$#" -ge 2 ] || die "--work-dir requires a value"; WORK_DIR="$2"; shift 2 ;;
		--release-base) [ "$#" -ge 2 ] || die "--release-base requires a value"; RELEASE_BASE="${2%/}"; shift 2 ;;
		--dtb)        [ "$#" -ge 2 ] || die "--dtb requires a value"; DTB="$2"; CUSTOM_DTB=1; shift 2 ;;
		--firmware-dir) [ "$#" -ge 2 ] || die "--firmware-dir requires a value"; FIRMWARE_DIR="$2"; shift 2 ;;
		--no-firmware) WITH_FIRMWARE=0; shift ;;
		--no-installer) WITH_INSTALLER=0; shift ;;
		--no-wifi-wizard) WITH_WIFI_WIZARD=0; shift ;;
		--with-extras) WITH_EXTRAS=1; shift ;;
		--no-extras) WITH_EXTRAS=0; shift ;;
		--write-sd) WRITE_SD=1; shift ;;
		--sd-device)  [ "$#" -ge 2 ] || die "--sd-device requires a value"; SD_DEVICE="$2"; WRITE_SD=1; shift 2 ;;
		--skip-download) DOWNLOAD=0; shift ;;
		-i|--interactive) WIZARD=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
done

[ "$(uname -s)" = "Linux" ] || die "this image builder must run on Linux"
[ "$(id -u)" -eq 0 ] || die "run as root; loop mount is required"

missing_pkgs=""
require_cmd blkid         util-linux
require_cmd curl          curl
require_cmd dtc           device-tree-compiler
require_cmd findmnt       util-linux
require_cmd gzip          gzip
require_cmd install       coreutils
require_cmd lsblk         util-linux
require_cmd losetup       util-linux
require_cmd mkimage       u-boot-tools
require_cmd mount         mount
require_cmd mountpoint    mount
require_cmd sha256sum     coreutils
require_cmd sync          coreutils
require_cmd umount        mount

CACHE_DIR="$WORK_DIR/cache"
mkdir -p "$CACHE_DIR"

# Auto-start the wizard only for a plain interactive invocation.
if [ "$WIZARD" -eq 0 ] && [ "$HAD_ARGS" -eq 0 ] && [ -t 0 ]; then
	WIZARD=1
fi

if [ "$WIZARD" -eq 1 ]; then
	wizard
	if [ "$WITH_FIRMWARE" -eq 0 ]; then
		FIRMWARE_DIR=""
		WITH_WIFI_WIZARD=0
	fi
fi

if [ "$WITH_FIRMWARE" -eq 1 ] && [ -z "$FIRMWARE_DIR" ]; then
	require_cmd 7z p7zip-full
fi

if [ -n "$missing_pkgs" ]; then
	log "Missing packages:$missing_pkgs"
	if [ "$WIZARD" -eq 1 ] && [ -r /dev/tty ]; then
		read -r -p "Install them with apt? [Y/n] " reply </dev/tty
		case "$reply" in
			[nN]*) die "install required packages manually: apt install$missing_pkgs" ;;
		esac
		# shellcheck disable=SC2086
		apt update && apt install -y $missing_pkgs
	else
		die "install required packages manually: apt install$missing_pkgs"
	fi
fi

# ── Asset status display ───────────────────────────────────────
log ""
log "=== Cubieboard4 A80 Debian 12 SD Image Builder ==="
log ""

log "Assets status:"
missing=0
check_asset() {
	local label="$1" path="$2"
	if [ -f "$path" ]; then log "  [OK]   $label"
	else log "  [MISS] $label"; missing=1; fi
}
check_asset "Boot image"            "$CACHE_DIR/$BOOT_ASSET"
check_asset "Debian rootfs"         "$CACHE_DIR/$ROOTFS_ASSET"
check_asset "Fixed U-Boot"          "$CACHE_DIR/$UBOOT_FIX_ASSET"
if [ "$WITH_FIRMWARE" -eq 1 ] && [ -z "$FIRMWARE_DIR" ]; then
	check_asset "Vendor SD (firmware)"  "$CACHE_DIR/$VENDOR_SD_ASSET"
else
	log "  [SKIP] Vendor SD (firmware)"
fi
if [ "$CUSTOM_DTB" -eq 1 ]; then
	[ -f "$DTB" ] || die "custom DTB not found: $DTB"
	log "  [OK]   Custom DTB ($DTB)"
elif [ -f "$DTS_SRC" ]; then
	log "  [OK]   DTS source ($DTS_SRC)"
elif [ -f "$CACHE_DIR/$DTS_ASSET" ]; then
	log "  [OK]   DTS source (cached: $CACHE_DIR/$DTS_ASSET)"
	DTS_SRC="$CACHE_DIR/$DTS_ASSET"
else
	log "  [MISS] $DTS_SRC"
	missing=1
fi
log ""

# ── DTS → DTB ──────────────────────────────────────────────────
log "--- DTS / DTB ---"
if [ "$CUSTOM_DTB" -eq 1 ]; then
	log "Using custom DTB: $DTB"
else
	download_dts_if_missing
	verify_sha256 "$DTS_SRC" "$DTS_SHA256"

	if [ ! -f "$DTB" ] || [ "$DTB" -ot "$DTS_SRC" ]; then
		log "Compiling DTB: $DTS_SRC -> $DTB"
		mkdir -p "$(dirname "$DTB")"
		dtc -I dts -O dtb -o "$DTB" "$DTS_SRC"
	else
		log "DTB is up to date: $DTB"
	fi
fi

# ── Build image ────────────────────────────────────────────────
if [ -z "$OUTPUT" ]; then
	OUTPUT="$WORK_DIR/cubieboard4-a80-debian12-sd.img"
fi
validate_output_path

ROOT_MOUNT="$WORK_DIR/mnt-root"
mkdir -p "$ROOT_MOUNT" "$(dirname "$OUTPUT")"
trap cleanup EXIT

log "--- Downloading assets ---"
download_asset "$BOOT_ASSET"
download_asset "$ROOTFS_ASSET"
verify_sha256 "$CACHE_DIR/$BOOT_ASSET" "$BOOT_SHA256"
verify_sha256 "$CACHE_DIR/$ROOTFS_ASSET" "$ROOTFS_SHA256"

log ""
log "--- Building SD image ---"
log "Creating image: $OUTPUT"
rm -f "$OUTPUT"
gzip -dc "$CACHE_DIR/$BOOT_ASSET" >"$OUTPUT"
gzip -dc "$CACHE_DIR/$ROOTFS_ASSET" >>"$OUTPUT"
sync "$OUTPUT" 2>/dev/null || sync

IMAGE_LOOP="$(attach_loop "$OUTPUT")"
root_part="$(partition_path "$IMAGE_LOOP" 2)"
log "Mounting generated rootfs: $root_part"
mount "$root_part" "$ROOT_MOUNT"

log ""
log "--- Patching image ---"
log "Installing validated DTB"
install -D -m 0644 "$DTB" "$ROOT_MOUNT/boot/sun9i-a80-cubieboard4.dtb"

log "Installing fixed U-Boot (eMMC clock register fix)"
download_asset "$UBOOT_FIX_ASSET"
verify_sha256 "$CACHE_DIR/$UBOOT_FIX_ASSET" "$UBOOT_FIX_SHA256"
install -D -m 0644 "$CACHE_DIR/$UBOOT_FIX_ASSET" "$ROOT_MOUNT/boot/u-boot-sunxi-with-spl.bin"

# ── Install helper scripts ────────────────────────────────────
if [ "$WITH_INSTALLER" -eq 1 ]; then
	log "Installing install-to-emmc.sh to /root/"
	if [ -f "$(dirname "$0")/install-to-emmc.sh" ]; then
		install -D -m 0755 "$(dirname "$0")/install-to-emmc.sh" "$ROOT_MOUNT/root/install-to-emmc.sh"
	else
		curl -sL --fail "$RAW_BASE/scripts/install-to-emmc.sh" -o "$ROOT_MOUNT/root/install-to-emmc.sh"
		chmod 0755 "$ROOT_MOUNT/root/install-to-emmc.sh"
	fi
else
	log "Skipping install-to-emmc.sh"
fi

if [ "$WITH_WIFI_WIZARD" -eq 1 ]; then
	log "Installing wifi-wizard.sh to /root/"
	if [ -f "$(dirname "$0")/wifi-wizard.sh" ]; then
		install -D -m 0755 "$(dirname "$0")/wifi-wizard.sh" "$ROOT_MOUNT/root/wifi-wizard.sh"
	else
		curl -sL --fail "$RAW_BASE/scripts/wifi-wizard.sh" -o "$ROOT_MOUNT/root/wifi-wizard.sh"
		chmod 0755 "$ROOT_MOUNT/root/wifi-wizard.sh"
	fi
else
	log "Skipping wifi-wizard.sh"
fi

write_sd_boot_script "$root_part" "$ROOT_MOUNT"

# ── WiFi firmware ──────────────────────────────────────────────
if [ "$WITH_FIRMWARE" -eq 1 ]; then
	if [ -n "$FIRMWARE_DIR" ]; then
		copy_ap6330_firmware "$FIRMWARE_DIR" "$ROOT_MOUNT"
	else
		extract_vendor_firmware
	fi
else
	log "Skipping AP6330 WiFi firmware"
fi

# ── Rootfs packages ────────────────────────────────────────────
ROOTFS_PKGS=""
if [ "$WITH_FIRMWARE" -eq 1 ] || [ "$WITH_WIFI_WIZARD" -eq 1 ]; then
	ROOTFS_PKGS="$ROOTFS_PKGS $WIFI_PKGS"
fi
if [ "$WITH_EXTRAS" -eq 1 ]; then
	ROOTFS_PKGS="$ROOTFS_PKGS $EXTRA_PKGS"
fi

if [ -z "${ROOTFS_PKGS## }" ]; then
	log "Skipping rootfs package installation"
	HAVE_QEMU=0
else
	log ""
	log "--- Installing rootfs packages ---"
	if command -v qemu-arm-static >/dev/null 2>&1; then
		HAVE_QEMU=1
	else
		log "qemu-arm-static not found (needed to install packages in the armhf rootfs)"
		if [ "$WIZARD" -eq 1 ] && [ -r /dev/tty ]; then
			read -r -p "Install qemu-user-static? [Y/n] " reply_qemu </dev/tty
			case "$reply_qemu" in
				[nN]*) HAVE_QEMU=0 ;;
				*)
					apt install -y qemu-user-static
					if command -v qemu-arm-static >/dev/null 2>&1; then HAVE_QEMU=1
					else log "qemu-user-static installation failed"; HAVE_QEMU=0; fi
					;;
			esac
		else
			HAVE_QEMU=0
		fi
	fi
fi

if [ "$HAVE_QEMU" -eq 1 ]; then
	log "Installing packages: $ROOTFS_PKGS"
	install -m 0755 "$(command -v qemu-arm-static)" "$ROOT_MOUNT/usr/bin/"
	[ -L "$ROOT_MOUNT/etc/resolv.conf" ] && RESOLV_ISLINK=1 || RESOLV_ISLINK=0
	rm -f "$ROOT_MOUNT/etc/resolv.conf"
	printf 'nameserver 8.8.8.8\n' >"$ROOT_MOUNT/etc/resolv.conf"
	mount --bind /proc "$ROOT_MOUNT/proc"
	mount --bind /dev "$ROOT_MOUNT/dev"
	mount --bind /sys "$ROOT_MOUNT/sys"
	mount --bind /dev/pts "$ROOT_MOUNT/dev/pts" 2>/dev/null || true
	chroot "$ROOT_MOUNT" apt update
	chroot "$ROOT_MOUNT" apt install -y $ROOTFS_PKGS
	umount "$ROOT_MOUNT/dev/pts" 2>/dev/null || true
	umount "$ROOT_MOUNT/sys"
	umount "$ROOT_MOUNT/dev"
	umount "$ROOT_MOUNT/proc"
	rm -f "$ROOT_MOUNT/usr/bin/qemu-arm-static" "$ROOT_MOUNT/etc/resolv.conf"
	log "Rootfs packages installed"
else
	log "Skipping package installation. Install manually on the CB4: apt install$ROOTFS_PKGS"
fi

sync
umount "$ROOT_MOUNT"
ROOT_MOUNT=""
losetup -d "$IMAGE_LOOP"
IMAGE_LOOP=""

if [ -n "$VENDOR_MOUNT" ] && mountpoint -q "$VENDOR_MOUNT"; then umount "$VENDOR_MOUNT"; fi
VENDOR_MOUNT=""
if [ -n "$VENDOR_LOOP" ]; then losetup -d "$VENDOR_LOOP"; VENDOR_LOOP=""; fi

log ""
log "Done: $OUTPUT"

# ── Write to SD ────────────────────────────────────────────────
if [ "$WRITE_SD" -eq 1 ]; then
	log ""
	if [ -z "$SD_DEVICE" ]; then
		choose_sd_device
	fi
	[ "$WRITE_SD" -eq 1 ] || exit 0
	[ -b "$SD_DEVICE" ] || die "not a block device: $SD_DEVICE"
	log ""
	log "WARNING: This will DESTROY ALL DATA on $SD_DEVICE"
	read -r -p "Are you sure? Type the device name to confirm ($(basename "$SD_DEVICE")): " confirm </dev/tty
	[ "$confirm" = "$(basename "$SD_DEVICE")" ] || die "confirmation mismatch, aborting"
	log "Writing $OUTPUT to $SD_DEVICE ..."
	dd if="$OUTPUT" of="$SD_DEVICE" bs=4M conv=sync status=progress
	sync
	log "Done. You can now remove the SD card."
fi
