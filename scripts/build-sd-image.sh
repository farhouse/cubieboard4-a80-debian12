#!/usr/bin/env bash
# build-sd-image.sh — Cubieboard4 A80 Debian 12 SD Image Builder
set -euo pipefail

SELF="$(basename "$0")"

RELEASE_BASE="https://github.com/farhouse/cubieboard4-a80-debian12/releases/download/external-images-2026-05"
RAW_BASE="https://raw.githubusercontent.com/farhouse/cubieboard4-a80-debian12/main"
WORK_DIR="build/sd-image"
OUTPUT=""
DTB="dtb/sun9i-a80-cubieboard4.dtb"
EXTRA_PKGS="parted wpasupplicant iw"
FIRMWARE_DIR=""
WITH_FIRMWARE=1
DOWNLOAD=1
INTERACTIVE=0
LOGFILE="/tmp/build-sd-image-$(date -u '+%Y%m%d-%H%M%S').log"

BOOT_ASSET="boot-cubieboard4.bin.gz"
ROOTFS_ASSET="debian-bookworm-armhf-vim3ve.bin.gz"
VENDOR_SD_ASSET="cb4-debian-server-hdmi-card-v1.0.img.7z"
UBOOT_FIX_ASSET="u-boot-sunxi-with-spl.bin"
DTB_ASSET="sun9i-a80-cubieboard4.dtb"

BOOT_SHA256="768d66822c61534083330951a4c6ce21493a892596f5a1fb86bef692ccda1411"
ROOTFS_SHA256="f9bc8b5e61599d4a680eca63ddd09dcde5392ba5161325e1031eef9b574adffb"
VENDOR_SD_SHA256="8af6f75dffa4b215fa40e254365f54de89510a2c0934b5ab4ac61e441eada3f5"
UBOOT_FIX_SHA256="56e1ce91b886be77673d9c27278a8ddf71775052085bc4b18583368a899e1f5d"
DTB_SHA256="da4b666a576e91e2aca9404d850f1c80c7ff4c5a79725764e534ac4b28571fb3"

CACHE_DIR=""
ROOT_MOUNT=""
VENDOR_MOUNT=""
IMAGE_LOOP=""
VENDOR_LOOP=""

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────
die()   { printf "\n${RED}✖ ERROR: %s${NC}\n" "$*" >&2; exit 1; }
step()  { printf "\n${CYAN}════════════════════════════════════════════════${NC}\n${BOLD}%s${NC}\n" "$*"; }
info()  { printf "  %s\n" "$*"; }
ok()    { printf "  ${GREEN}✔ %s${NC}\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠ %s${NC}\n" "$*"; }
log()   { printf "[%s] %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOGFILE"; }
sep()   { printf "  ${CYAN}────────────────────────────────────────────${NC}\n"; }

prompt_yn() {
	local prompt="$1 [Y/n] " reply
	read -r -p "$prompt" reply </dev/tty
	case "$reply" in [nN]*) return 1;; *) return 0;; esac
}

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		missing_pkgs="$missing_pkgs $2"
		return 1
	fi
	return 0
}

show_progress() {
	local desc="$1" pid=$2
	while kill -0 "$pid" 2>/dev/null; do
		printf "\r  ${desc}..."
		sleep 1
	done
	wait "$pid" && printf "\r  ${GREEN}✔${NC} ${desc}  \n" || { printf "\r  ${RED}✖${NC} ${desc}  \n"; return 1; }
}

cleanup() {
	set +e
	if [ -n "$ROOT_MOUNT" ] && mountpoint -q "$ROOT_MOUNT" 2>/dev/null; then
		umount "$ROOT_MOUNT" 2>/dev/null
	fi
	if [ -n "$VENDOR_MOUNT" ] && mountpoint -q "$VENDOR_MOUNT" 2>/dev/null; then
		umount "$VENDOR_MOUNT" 2>/dev/null
	fi
	if [ -n "$IMAGE_LOOP" ]; then
		losetup -d "$IMAGE_LOOP" >/dev/null 2>&1
	fi
	if [ -n "$VENDOR_LOOP" ]; then
		losetup -d "$VENDOR_LOOP" >/dev/null 2>&1
	fi
}

# ── Core functions ─────────────────────────────────────────────
usage() {
	cat <<EOF
Usage:
  sudo $SELF [options]
  sudo $SELF --interactive
  curl -sL ... | sudo bash -s -- --interactive

Builds a Cubieboard4 Debian 12 SD image from preserved release assets, then
patches the root filesystem with the validated DTB and AP6330 WiFi firmware.

Options:
  --interactive         Step-by-step wizard mode (default when no options given)
  --output FILE         Final image path (default: WORK_DIR/cb4...sd.img)
  --work-dir DIR        Cache and temporary files (default: $WORK_DIR)
  --release-base URL    Override the GitHub Release download base URL
  --dtb FILE            DTB to install (default: $DTB)
  --firmware-dir DIR    Use AP6330 firmware from DIR instead of vendor image
  --no-firmware         Do not install AP6330 WiFi firmware
  --skip-download       Reuse already cached assets only
  -h, --help            Show this help
EOF
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
	if command -v curl >/dev/null 2>&1; then
		curl -L --fail --output "$dest.tmp" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$dest.tmp" "$url"
	else
		die "required command not found: curl or wget"
	fi
	mv "$dest.tmp" "$dest"
}

verify_sha256() {
	local file="$1"
	local expected="$2"
	info "Verifying SHA256: $(basename "$file")"
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

# ── Wizard steps ───────────────────────────────────────────────
welcome() {
	clear
	cat <<WELCOME
${BOLD}╔══════════════════════════════════════════════════════════╗
║  Cubieboard4 A80 — Debian 12 SD Image Builder (Wizard)║
╚══════════════════════════════════════════════════════════╝${NC}

This tool builds a reproducible SD image for the Cubieboard4 A80.

It will:
  • Download boot + rootfs + firmware assets from GitHub Release
  • Concatenate them into a bootable SD image
  • Patch with validated DTB and fixed U-Boot (eMMC clock fix)
  • Install AP6330 WiFi firmware
  • Generate boot.scr with root=UUID=...
  • Optionally install extra packages via QEMU chroot
  • Optionally write the image to an SD card

WELCOME

	if [ -f "$LOGFILE" ]; then
		info "Log: $LOGFILE"
	fi

	if prompt_yn "Begin?"; then
		log "=== Session started (interactive) ==="
		return 0
	else
		die "exiting"
	fi
}

check_prereqs() {
	step "Prerequisites"
	missing_pkgs=""
	require_cmd blkid       util-linux
	require_cmd curl         curl
	require_cmd gzip         gzip
	require_cmd install      coreutils
	require_cmd losetup      util-linux
	require_cmd mkimage      u-boot-tools
	require_cmd mount        mount
	require_cmd sha256sum    coreutils
	require_cmd sync         coreutils

	if [ "$WITH_FIRMWARE" -eq 1 ] && [ -z "$FIRMWARE_DIR" ]; then
		require_cmd 7z  p7zip-full
	fi

	if [ -z "$missing_pkgs" ]; then
		ok "all required packages present"
		return 0
	fi

	warn "Missing packages:$missing_pkgs"
	if prompt_yn "Install them with apt?"; then
		# shellcheck disable=SC2086
		apt update && apt install -y $missing_pkgs
		ok "packages installed"
	else
		die "install required packages: apt install$missing_pkgs"
	fi
}

show_asset_status() {
	step "Asset Status"
	missing=0

	check_one() {
		local label="$1" path="$2"
		if [ -f "$path" ]; then
			info "  [OK]   $label"
		else
			warn "  [MISS] $label"
			missing=1
		fi
	}

	check_one "Boot image"           "$CACHE_DIR/$BOOT_ASSET"
	check_one "Debian rootfs"        "$CACHE_DIR/$ROOTFS_ASSET"
	check_one "Fixed U-Boot"         "$CACHE_DIR/$UBOOT_FIX_ASSET"
	check_one "Vendor SD (firmware)" "$CACHE_DIR/$VENDOR_SD_ASSET"
	if [ -f "$DTB" ]; then
		info "  [OK]   DTB ($DTB)"
	else
		check_one "DTB" "$CACHE_DIR/$DTB_ASSET"
	fi
	echo ""

	if [ "$missing" -eq 1 ]; then
		if [ "$DOWNLOAD" -eq 1 ]; then
			if prompt_yn "Download missing assets?"; then
				return 0
			else
				die "aborted by user"
			fi
		else
			die "missing assets and --skip-download was used"
		fi
	fi
}

download_all_assets() {
	step "Download Assets"
	local pids=()

	download_asset "$BOOT_ASSET" &
	pids+=($!)
	download_asset "$ROOTFS_ASSET" &
	pids+=($!)
	download_asset "$UBOOT_FIX_ASSET" &
	pids+=($!)

	if [ "$WITH_FIRMWARE" -eq 1 ] && [ -z "$FIRMWARE_DIR" ]; then
		download_asset "$VENDOR_SD_ASSET" &
		pids+=($!)
	fi

	if [ ! -f "$DTB" ]; then
		download_asset "$DTB_ASSET" &
		pids+=($!)
	fi

	local errors=0
	for pid in "${pids[@]}"; do
		wait "$pid" || errors=$((errors + 1))
	done

	[ "$errors" -eq 0 ] || die "$errors download(s) failed"

	verify_sha256 "$CACHE_DIR/$BOOT_ASSET" "$BOOT_SHA256"
	verify_sha256 "$CACHE_DIR/$ROOTFS_ASSET" "$ROOTFS_SHA256"
	verify_sha256 "$CACHE_DIR/$UBOOT_FIX_ASSET" "$UBOOT_FIX_SHA256"
	if [ "$WITH_FIRMWARE" -eq 1 ] && [ -z "$FIRMWARE_DIR" ]; then
		verify_sha256 "$CACHE_DIR/$VENDOR_SD_ASSET" "$VENDOR_SD_SHA256"
	fi
	if [ ! -f "$DTB" ]; then
		DTB="$CACHE_DIR/$DTB_ASSET"
		verify_sha256 "$DTB" "$DTB_SHA256"
	fi

	ok "all assets downloaded and verified"
}

select_output_path() {
	step "Output Path"
	if [ -z "$OUTPUT" ]; then
		OUTPUT="$WORK_DIR/cubieboard4-a80-debian12-sd.img"
	fi
	read -r -p "Output image path [$OUTPUT]: " reply </dev/tty
	[ -n "$reply" ] && OUTPUT="$reply"
	validate_output_path
	ok "output: $OUTPUT"
}

validate_output_path() {
	case "$OUTPUT" in
		/dev/*) die "--output must be an image file path, not a block device: $OUTPUT" ;;
	esac
	[ ! -b "$OUTPUT" ] || die "--output points to a block device: $OUTPUT"
	[ ! -d "$OUTPUT" ] || die "--output points to a directory: $OUTPUT"
	[ ! -L "$OUTPUT" ] || die "--output must not be a symlink: $OUTPUT"
	if [ -e "$OUTPUT" ] && [ ! -f "$OUTPUT" ]; then
		die "--output exists but is not a regular file: $OUTPUT"
	fi
}

build_image() {
	step "Build SD Image"
	if [ -f "$OUTPUT" ]; then
		warn "Output file exists: $OUTPUT ($(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null) bytes)"
		if ! prompt_yn "Overwrite?"; then
			warn "build skipped"
			return 1
		fi
	fi

	info "Concatenating boot + rootfs..."
	(
		rm -f "$OUTPUT"
		gzip -dc "$CACHE_DIR/$BOOT_ASSET" >"$OUTPUT"
		gzip -dc "$CACHE_DIR/$ROOTFS_ASSET" >>"$OUTPUT"
		sync "$OUTPUT" 2>/dev/null || sync
	) &
	show_progress "Building image" $!

	OUTPUT_SIZE="$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null || echo "?")"
	ok "image created: $OUTPUT ($(( OUTPUT_SIZE / 1024 / 1024 )) MiB)"
}

mount_image() {
	ROOT_MOUNT="$WORK_DIR/mnt-root"
	mkdir -p "$ROOT_MOUNT" "$(dirname "$OUTPUT")"

	IMAGE_LOOP="$(attach_loop "$OUTPUT")"
	local root_part
	root_part="$(partition_path "$IMAGE_LOOP" 2)"
	mount "$root_part" "$ROOT_MOUNT"
	log "Mounted $root_part -> $ROOT_MOUNT"
}

unmount_image() {
	if mountpoint -q "$ROOT_MOUNT" 2>/dev/null; then
		sync
		umount "$ROOT_MOUNT" || true
	fi
	if [ -n "$IMAGE_LOOP" ]; then
		losetup -d "$IMAGE_LOOP" 2>/dev/null || true
		IMAGE_LOOP=""
	fi
}

patch_image() {
	step "Patch Image"
	mount_image

	info "Installing validated DTB..."
	install -D -m 0644 "$DTB" "$ROOT_MOUNT/boot/sun9i-a80-cubieboard4.dtb"

	info "Installing fixed U-Boot..."
	install -D -m 0644 "$CACHE_DIR/$UBOOT_FIX_ASSET" "$ROOT_MOUNT/boot/u-boot-sunxi-with-spl.bin"

	if prompt_yn "Include install-to-emmc.sh on the image?"; then
		if [ -f "$(dirname "$0")/install-to-emmc.sh" ]; then
			install -D -m 0755 "$(dirname "$0")/install-to-emmc.sh" "$ROOT_MOUNT/root/install-to-emmc.sh"
		else
			info "Downloading install-to-emmc.sh from upstream..."
			curl -sL --fail "$RAW_BASE/scripts/install-to-emmc.sh" \
				-o "$ROOT_MOUNT/root/install-to-emmc.sh"
			chmod 0755 "$ROOT_MOUNT/root/install-to-emmc.sh"
		fi
		ok "install-to-emmc.sh installed to /root/"
	fi

	# Generate boot.scr
	local root_part
	root_part="$(partition_path "$IMAGE_LOOP" 2)"
	write_sd_boot_script "$root_part" "$ROOT_MOUNT"
	ok "boot.scr generated"

	unmount_image
}

write_sd_boot_script() {
	local root_part="$1" root_mount="$2"
	local root_uuid kernel_version boot_cmd="$root_mount/boot/boot.cmd"

	root_uuid="$(blkid -s UUID -o value "$root_part")"
	[ -n "$root_uuid" ] || die "could not determine rootfs UUID for: $root_part"
	kernel_version="$(detect_kernel_version "$root_mount")"

	info "SD boot script: root=UUID=$root_uuid kernel=$kernel_version"
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

detect_kernel_version() {
	local boot_dir="$1/boot" kernel="" path
	for path in "$boot_dir"/vmlinuz-*; do
		[ -f "$path" ] || continue
		kernel="$(basename "$path")"
	done
	[ -n "$kernel" ] || die "could not find kernel in: $boot_dir"
	printf '%s\n' "${kernel#vmlinuz-}"
}

extract_vendor_firmware() {
	local archive="$CACHE_DIR/$VENDOR_SD_ASSET"
	local extract_dir="$WORK_DIR/vendor-sd"
	local vendor_img="$extract_dir/cb4-debian-server-hdmi-card-v1.0.img"
	local vendor_root

	require_cmd 7z || die "7z is required to extract vendor image (use --firmware-dir to skip)"

	info "Extracting vendor image for AP6330 firmware..."
	mkdir -p "$extract_dir"

	if [ ! -f "$vendor_img" ]; then
		7z x -y "-o$extract_dir" "$archive" >/dev/null
	fi
	[ -f "$vendor_img" ] || die "vendor image not found after extraction: $vendor_img"

	VENDOR_MOUNT="$WORK_DIR/mnt-vendor"
	mkdir -p "$VENDOR_MOUNT"
	VENDOR_LOOP="$(attach_loop "$vendor_img")"
	vendor_root="$(partition_path "$VENDOR_LOOP" 2)"
	mount -o ro "$vendor_root" "$VENDOR_MOUNT"

	copy_ap6330_firmware "$VENDOR_MOUNT/lib/firmware/ap6330"
}

copy_ap6330_firmware() {
	local src_dir="$1"
	local target_dir="$ROOT_MOUNT/lib/firmware/brcm"
	local fw_bin="$src_dir/fw_bcm40183b2_ag.bin"
	local fw_txt="$src_dir/nvram_ap6330.txt"

	[ -f "$fw_bin" ] || die "missing AP6330 firmware: $fw_bin"
	[ -f "$fw_txt" ] || die "missing AP6330 NVRAM: $fw_txt"

	install -d "$target_dir"
	install -m 0644 "$fw_bin" "$target_dir/brcmfmac4330-sdio.bin"
	install -m 0644 "$fw_txt" "$target_dir/brcmfmac4330-sdio.txt"
	ok "AP6330 firmware installed"
}

install_firmware() {
	step "Install WiFi Firmware"
	mount_image

	if [ -n "$FIRMWARE_DIR" ]; then
		copy_ap6330_firmware "$FIRMWARE_DIR"
	else
		extract_vendor_firmware
	fi

	unmount_image
}

install_extra_packages() {
	step "Extra Packages"
	mount_image

	if ! command -v qemu-arm-static >/dev/null 2>&1; then
		warn "qemu-arm-static not found"
		if prompt_yn "Install qemu-user-static?"; then
			apt install -y qemu-user-static
		else
			unmount_image
			warn "skipping extra packages. Install manually: apt install $EXTRA_PKGS"
			return
		fi
	fi

	info "Installing: $EXTRA_PKGS"
	install -m 0755 "$(command -v qemu-arm-static)" "$ROOT_MOUNT/usr/bin/"
	[ -L "$ROOT_MOUNT/etc/resolv.conf" ] && RESOLV_ISLINK=1 || RESOLV_ISLINK=0
	rm -f "$ROOT_MOUNT/etc/resolv.conf"
	printf 'nameserver 8.8.8.8\n' >"$ROOT_MOUNT/etc/resolv.conf"
	mount --bind /proc "$ROOT_MOUNT/proc"
	mount --bind /dev "$ROOT_MOUNT/dev"
	mount --bind /sys "$ROOT_MOUNT/sys"
	mount --bind /dev/pts "$ROOT_MOUNT/dev/pts" 2>/dev/null || true

	if chroot "$ROOT_MOUNT" apt update >/dev/null 2>&1; then
		chroot "$ROOT_MOUNT" apt install -y $EXTRA_PKGS 2>&1
		ok "extra packages installed"
	else
		warn "chroot apt update failed (no network in chroot?)"
		warn "Install manually: apt install $EXTRA_PKGS"
	fi

	umount "$ROOT_MOUNT/dev/pts" 2>/dev/null || true
	umount "$ROOT_MOUNT/sys"
	umount "$ROOT_MOUNT/dev"
	umount "$ROOT_MOUNT/proc"
	rm -f "$ROOT_MOUNT/usr/bin/qemu-arm-static" "$ROOT_MOUNT/etc/resolv.conf"

	unmount_image
}

write_to_sd() {
	step "Write to SD Card"
	if ! prompt_yn "Write image to an SD card?"; then
		info "skipped"
		return
	fi

	# Discover writable block devices (not loop, not source of /)
	SOURCE_DISK="$(findmnt -n -o SOURCE / 2>/dev/null || echo "")"
	SOURCE_DISK="$(lsblk -n -o PKNAME "$SOURCE_DISK" 2>/dev/null || echo "")"

	AVAILABLE=()
	while IFS= read -r line; do
		AVAILABLE+=("$line")
	done < <(lsblk -dno NAME,SIZE,MODEL,TRAN 2>/dev/null | grep -v loop || true)

	if [ ${#AVAILABLE[@]} -eq 0 ]; then
		die "no writable block devices found"
	fi

	echo ""
	info "Available devices:"
	sep
	for i in "${!AVAILABLE[@]}"; do
		printf "  %d) /dev/%s\n" $((i+1)) "${AVAILABLE[i]}"
	done
	sep
	echo ""

	read -r -p "Select device number: " reply </dev/tty
	[ -n "$reply" ] && [ "$reply" -eq "$reply" ] 2>/dev/null || die "invalid selection"
	idx=$((reply-1))
	[ "$idx" -ge 0 ] && [ "$idx" -lt "${#AVAILABLE[@]}" ] || die "invalid selection"
	SD_DEV="/dev/$(echo "${AVAILABLE[idx]}" | awk '{print $1}')"

	[ -b "$SD_DEV" ] || die "not a block device: $SD_DEV"

	# Warning
	echo ""
	warn "DESTROY ALL DATA on $SD_DEV ($(lsblk -dno SIZE "$SD_DEV" 2>/dev/null))"
	read -r -p "Type $(basename "$SD_DEV") to confirm: " confirm </dev/tty
	[ "$confirm" = "$(basename "$SD_DEV")" ] || die "confirmation mismatch"

	info "Writing $OUTPUT to $SD_DEV..."
	dd "if=$OUTPUT" "of=$SD_DEV" bs=4M conv=sync status=progress
	sync
	ok "image written to $SD_DEV"
	info "Remove the SD card and insert it into the Cubieboard4."
}

# ── Step selection ─────────────────────────────────────────────
select_steps() {
	step "Step Selection"
	info "Choose which steps to run:"
	sep

	steps=(
		"Check prerequisites"
		"Download assets"
		"Set output path"
		"Build SD image"
		"Patch image (DTB, U-Boot, boot.scr, installer)"
		"Install WiFi firmware (AP6330)"
		"Install extra packages (QEMU chroot)"
		"Write to SD card"
	)

	# All enabled by default
	run_step=()
	for i in "${!steps[@]}"; do
		printf "  %2d) %s\n" $((i+1)) "${steps[i]}"
		run_step[i]=1
	done
	sep
	echo ""

	read -r -p "Enter step numbers to SKIP (e.g. '6 8'), or press Enter for all: " reply </dev/tty
	if [ -n "$reply" ]; then
		for num in $reply; do
			idx=$((num-1))
			[ "$idx" -ge 0 ] && [ "$idx" -lt "${#steps[@]}" ] && run_step[idx]=0 || warn "invalid step: $num"
		done
	fi

	echo ""
	info "Steps marked to run:"
	for i in "${!steps[@]}"; do
		[ "${run_step[i]}" -eq 1 ] && printf "  ${GREEN}✔${NC}  %s\n" "${steps[i]}"
	done
	sep

	if prompt_yn "Continue?"; then return 0; else select_steps; fi
}

show_plan() {
	step "Plan"
	OUTPUT_SIZE_HUMAN="?"
	[ -f "$OUTPUT" ] && OUTPUT_SIZE_HUMAN="$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null || echo "?")"

	cat <<PLAN

  ${BOLD}Summary${NC}
  Output:  $OUTPUT
  DTB:     $DTB
  Firmware:$([ "$WITH_FIRMWARE" -eq 0 ] && echo " none" || [ -n "$FIRMWARE_DIR" ] && echo " $FIRMWARE_DIR" || echo " from vendor image")
  Work:    $WORK_DIR

  ${BOLD}Steps${NC}
PLAN

	DESCS=("Check prerequisites" "Download assets" "Set output path" "Build SD image" "Patch image" "Install WiFi firmware" "Install extra packages" "Write to SD card")
	for i in "${!DESCS[@]}"; do
		[ "${run_step[i]:-0}" -eq 1 ] && printf "  ${GREEN}✔${NC}  %s\n" "${DESCS[i]}" || printf "  ${RED}✖${NC}  %s\n" "${DESCS[i]}"
	done
	echo ""

	if ! prompt_yn "Execute this plan?"; then
		die "aborted"
	fi
}

do_step() {
	local num="$1" desc="$2"
	shift 2
	if [ "${run_step[num]:-0}" -eq 1 ]; then
		log "--- Step $((num+1)): $desc ---"
		"$@"
		log "--- Step $((num+1)) complete ---"
	else
		info "[skip] $desc"
	fi
}

print_summary() {
	step "Done"
	OUTPUT_SIZE="$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null || echo "?")"
	cat <<SUMMARY

  ${BOLD}Image built successfully!${NC}

  Output: $OUTPUT
  Size:   $(( OUTPUT_SIZE / 1024 / 1024 )) MiB
  SHA256: $(sha256sum "$OUTPUT" 2>/dev/null | awk '{print $1}' || echo "?")

  ${BOLD}Next steps:${NC}
  1. Write to SD: dd if=$OUTPUT of=/dev/sdX bs=4M conv=sync status=progress
  2. Insert SD into Cubieboard4 and boot
  3. Run /root/install-to-emmc.sh (if included) to install to eMMC

  Log: $LOGFILE

SUMMARY
}

# ── Wizard ──────────────────────────────────────────────────────
wizard_main() {
	CACHE_DIR="$WORK_DIR/cache"
	mkdir -p "$CACHE_DIR"
	trap cleanup EXIT

	welcome

	while true; do
		select_steps

		do_step 0 "Check prerequisites"    check_prereqs

		# Must have CACHE_DIR set
		CACHE_DIR="$WORK_DIR/cache"
		mkdir -p "$CACHE_DIR"

		show_asset_status
		do_step 1 "Download assets"        download_all_assets
		do_step 2 "Set output path"        select_output_path
		do_step 3 "Build SD image"         build_image
		do_step 4 "Patch image"            patch_image
		do_step 5 "Install WiFi firmware"  install_firmware
		do_step 6 "Install extra packages" install_extra_packages
		do_step 7 "Write to SD card"       write_to_sd

		print_summary

		if prompt_yn "Run again with different options?"; then
			continue
		else
			break
		fi
	done
}

# ── CLI mode ────────────────────────────────────────────────────
cli_main() {
	[ "$(uname -s)" = "Linux" ] || die "this image builder must run on Linux"
	[ "$(id -u)" -eq 0 ] || die "run as root; loop mount is required"

	missing_pkgs=""
	require_cmd blkid         util-linux
	require_cmd curl          curl
	require_cmd gzip          gzip
	require_cmd install       coreutils
	require_cmd losetup       util-linux
	require_cmd mkimage       u-boot-tools
	require_cmd mount         mount
	require_cmd mountpoint    mount
	require_cmd sha256sum     coreutils
	require_cmd sync          coreutils
	require_cmd umount        mount

	if [ "$WITH_FIRMWARE" -eq 1 ] && [ -z "$FIRMWARE_DIR" ]; then
		require_cmd 7z  p7zip-full
	fi

	if [ -n "$missing_pkgs" ]; then
		log "Missing packages:$missing_pkgs"
		# shellcheck disable=SC2086
		apt update && apt install -y $missing_pkgs
	fi

	CACHE_DIR="$WORK_DIR/cache"
	ROOT_MOUNT="$WORK_DIR/mnt-root"
	mkdir -p "$CACHE_DIR" "$ROOT_MOUNT" "$(dirname "$OUTPUT")"
	trap cleanup EXIT

	[ -z "$OUTPUT" ] && OUTPUT="$WORK_DIR/cubieboard4-a80-debian12-sd.img"
	validate_output_path

	log "=== Cubieboard4 A80 Debian 12 SD Image Builder (CLI) ==="
	log "Output: $OUTPUT"

	download_asset "$BOOT_ASSET"
	download_asset "$ROOTFS_ASSET"
	download_asset "$UBOOT_FIX_ASSET"

	verify_sha256 "$CACHE_DIR/$BOOT_ASSET" "$BOOT_SHA256"
	verify_sha256 "$CACHE_DIR/$ROOTFS_ASSET" "$ROOTFS_SHA256"
	verify_sha256 "$CACHE_DIR/$UBOOT_FIX_ASSET" "$UBOOT_FIX_SHA256"

	if [ ! -f "$DTB" ]; then
		download_asset "$DTB_ASSET"
		verify_sha256 "$CACHE_DIR/$DTB_ASSET" "$DTB_SHA256"
		DTB="$CACHE_DIR/$DTB_ASSET"
	fi

	log "Creating image..."
	rm -f "$OUTPUT"
	gzip -dc "$CACHE_DIR/$BOOT_ASSET" >"$OUTPUT"
	gzip -dc "$CACHE_DIR/$ROOTFS_ASSET" >>"$OUTPUT"
	sync "$OUTPUT" 2>/dev/null || sync

	IMAGE_LOOP="$(attach_loop "$OUTPUT")"
	root_part="$(partition_path "$IMAGE_LOOP" 2)"
	mount "$root_part" "$ROOT_MOUNT"

	log "Patching image..."
	install -D -m 0644 "$DTB" "$ROOT_MOUNT/boot/sun9i-a80-cubieboard4.dtb"
	install -D -m 0644 "$CACHE_DIR/$UBOOT_FIX_ASSET" "$ROOT_MOUNT/boot/u-boot-sunxi-with-spl.bin"

	write_sd_boot_script "$root_part" "$ROOT_MOUNT"

	if [ "$WITH_FIRMWARE" -eq 1 ]; then
		if [ -n "$FIRMWARE_DIR" ]; then
			copy_ap6330_firmware "$FIRMWARE_DIR"
		else
			log "Extracting firmware from vendor image..."
			extract_vendor_firmware
		fi
	fi

	sync
	umount "$ROOT_MOUNT"
	ROOT_MOUNT=""
	losetup -d "$IMAGE_LOOP"
	IMAGE_LOOP=""

	if [ -n "$VENDOR_MOUNT" ] && mountpoint -q "$VENDOR_MOUNT" 2>/dev/null; then
		umount "$VENDOR_MOUNT"
		VENDOR_MOUNT=""
	fi
	if [ -n "$VENDOR_LOOP" ]; then
		losetup -d "$VENDOR_LOOP"
		VENDOR_LOOP=""
	fi

	OUTPUT_SIZE="$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null || echo "?")"
	log "Done: $OUTPUT ($(( OUTPUT_SIZE / 1024 / 1024 )) MiB)"
}

# ── Parse args ─────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
	case "$1" in
		--interactive)    INTERACTIVE=1; shift ;;
		--output)         [ "$#" -ge 2 ] || die "--output requires a value"; OUTPUT="$2"; shift 2 ;;
		--work-dir)       [ "$#" -ge 2 ] || die "--work-dir requires a value"; WORK_DIR="${2%/}"; shift 2 ;;
		--release-base)   [ "$#" -ge 2 ] || die "--release-base requires a value"; RELEASE_BASE="${2%/}"; shift 2 ;;
		--dtb)            [ "$#" -ge 2 ] || die "--dtb requires a value"; DTB="$2"; shift 2 ;;
		--firmware-dir)   [ "$#" -ge 2 ] || die "--firmware-dir requires a value"; FIRMWARE_DIR="$2"; shift 2 ;;
		--no-firmware)    WITH_FIRMWARE=0; shift ;;
		--skip-download)  DOWNLOAD=0; shift ;;
		-h|--help)        usage; exit 0 ;;
		*)                die "unknown argument: $1" ;;
	esac
done

# ── Entry point ────────────────────────────────────────────────
# Auto-detect: force CLI mode only if /dev/tty is totally inaccessible
# (CI environments, Docker without -t). Pipe (curl | bash) still has /dev/tty.
if [ "$INTERACTIVE" -eq 0 ] && ! (exec <>/dev/tty) 2>/dev/null; then
	INTERACTIVE=0
fi


