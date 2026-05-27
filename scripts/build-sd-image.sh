#!/usr/bin/env bash
set -euo pipefail

SELF="$(basename "$0")"

RELEASE_BASE="https://github.com/farhouse/cubieboard4-a80-debian12/releases/download/external-images-2026-05"
RAW_BASE="https://raw.githubusercontent.com/farhouse/cubieboard4-a80-debian12/main"
WORK_DIR="build/sd-image"
OUTPUT=""
DTB="dtb/sun9i-a80-cubieboard4.dtb"
FIRMWARE_DIR=""
WITH_FIRMWARE=1
DOWNLOAD=1

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

usage() {
	cat <<EOF
Usage:
  sudo $SELF [--output FILE] [--work-dir DIR]

Builds a Cubieboard4 Debian 12 SD image from preserved release assets, then
patches the root filesystem with the validated DTB and AP6330 WiFi firmware.

Default assets:
  release: $RELEASE_BASE
  boot:    $BOOT_ASSET
  rootfs:  $ROOTFS_ASSET
  vendor:  $VENDOR_SD_ASSET
  dtb:     $DTB_ASSET
  uboot:   $UBOOT_FIX_ASSET (fixed eMMC clock register)

Options:
  --output FILE        Final image path.
                       Default: WORK_DIR/cubieboard4-a80-debian12-sd.img
  --work-dir DIR       Cache and temporary files, default: $WORK_DIR.
  --release-base URL   Override the GitHub Release download base URL.
  --dtb FILE           DTB to install, default: $DTB.
  --firmware-dir DIR   Use AP6330 firmware from DIR instead of vendor image.
                       Expected files: fw_bcm40183b2_ag.bin, nvram_ap6330.txt
  --no-firmware        Do not install AP6330 WiFi firmware.
  --skip-download      Reuse already cached assets only.
  -h, --help           Show this help.

Requirements:
  Linux root shell with curl or wget, sha256sum, gzip, blkid, losetup, mount,
  umount, and mkimage from u-boot-tools. 7z is also required unless
  --firmware-dir or --no-firmware is used.
EOF
}

log() {
	printf '%s\n' "$*"
}

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
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
	local target_dir="$2/lib/firmware/brcm"
	local fw_bin="$src_dir/fw_bcm40183b2_ag.bin"
	local fw_txt="$src_dir/nvram_ap6330.txt"

	[ -f "$fw_bin" ] || die "missing AP6330 firmware: $fw_bin"
	[ -f "$fw_txt" ] || die "missing AP6330 NVRAM: $fw_txt"

	log "Installing AP6330 WiFi firmware"
	install -d "$target_dir"
	install -m 0644 "$fw_bin" "$target_dir/brcmfmac4330-sdio.bin"
	install -m 0644 "$fw_txt" "$target_dir/brcmfmac4330-sdio.txt"
}

detect_kernel_version() {
	local boot_dir="$1/boot"
	local kernel=""
	local path

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
	local root_uuid
	local kernel_version
	local boot_cmd="$root_mount/boot/boot.cmd"

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
	case "$OUTPUT" in
		/dev/*)
			die "--output must be an image file path, not a block device: $OUTPUT"
			;;
	esac

	[ ! -b "$OUTPUT" ] || die "--output points to a block device: $OUTPUT"
	[ ! -d "$OUTPUT" ] || die "--output points to a directory: $OUTPUT"
	[ ! -L "$OUTPUT" ] || die "--output must not be a symlink: $OUTPUT"
	if [ -e "$OUTPUT" ] && [ ! -f "$OUTPUT" ]; then
		die "--output exists but is not a regular file: $OUTPUT"
	fi
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

while [ "$#" -gt 0 ]; do
	case "$1" in
		--output)
			[ "$#" -ge 2 ] || die "--output requires a value"
			OUTPUT="$2"
			shift 2
			;;
		--work-dir)
			[ "$#" -ge 2 ] || die "--work-dir requires a value"
			WORK_DIR="$2"
			shift 2
			;;
		--release-base)
			[ "$#" -ge 2 ] || die "--release-base requires a value"
			RELEASE_BASE="${2%/}"
			shift 2
			;;
		--dtb)
			[ "$#" -ge 2 ] || die "--dtb requires a value"
			DTB="$2"
			shift 2
			;;
		--firmware-dir)
			[ "$#" -ge 2 ] || die "--firmware-dir requires a value"
			FIRMWARE_DIR="$2"
			shift 2
			;;
		--no-firmware)
			WITH_FIRMWARE=0
			shift
			;;
		--skip-download)
			DOWNLOAD=0
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown argument: $1"
			;;
	esac
done

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
	read -r -p "Install them with apt? [Y/n] " reply </dev/tty
	case "$reply" in
		[nN]*) die "install required packages manually: apt install$missing_pkgs" ;;
	esac
	# shellcheck disable=SC2086
	apt update && apt install -y $missing_pkgs
fi

CACHE_DIR="$WORK_DIR/cache"
mkdir -p "$CACHE_DIR"

log "=== Cubieboard4 A80 Debian 12 SD Image Builder ==="
log ""

log ""
log "Assets status:"
missing=0
check_asset() {
	local label="$1"
	local path="$2"
	if [ -f "$path" ]; then
		log "  [OK]   $label"
	else
		log "  [MISS] $label"
		missing=1
	fi
}

check_asset "Boot image"            "$CACHE_DIR/$BOOT_ASSET"
check_asset "Debian rootfs"         "$CACHE_DIR/$ROOTFS_ASSET"
check_asset "Fixed U-Boot"          "$CACHE_DIR/$UBOOT_FIX_ASSET"
check_asset "Vendor SD (firmware)"  "$CACHE_DIR/$VENDOR_SD_ASSET"
if [ -f "$DTB" ]; then
	log "  [OK]   DTB ($DTB)"
else
	check_asset "DTB" "$CACHE_DIR/$DTB_ASSET"
fi
log ""

if [ "$DOWNLOAD" -eq 1 ] && [ "$missing" -eq 1 ]; then
	read -r -p "Download missing assets? [Y/n] " reply </dev/tty
	case "$reply" in
		[nN]*) die "aborted by user" ;;
	esac
fi

if [ ! -f "$DTB" ]; then
	log "DTB not found locally, will download from release"
	download_asset "$DTB_ASSET"
	verify_sha256 "$CACHE_DIR/$DTB_ASSET" "$DTB_SHA256"
	DTB="$CACHE_DIR/$DTB_ASSET"
fi

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

log "Installing install-to-emmc.sh to /root/"
if [ -f "$(dirname "$0")/install-to-emmc.sh" ]; then
	install -D -m 0755 "$(dirname "$0")/install-to-emmc.sh" "$ROOT_MOUNT/root/install-to-emmc.sh"
else
	log "Downloading install-to-emmc.sh from upstream"
	curl -sL --fail "$RAW_BASE/scripts/install-to-emmc.sh" \
		-o "$ROOT_MOUNT/root/install-to-emmc.sh"
	chmod 0755 "$ROOT_MOUNT/root/install-to-emmc.sh"
fi

write_sd_boot_script "$root_part" "$ROOT_MOUNT"

if [ "$WITH_FIRMWARE" -eq 1 ]; then
	if [ -n "$FIRMWARE_DIR" ]; then
		copy_ap6330_firmware "$FIRMWARE_DIR" "$ROOT_MOUNT"
	else
		extract_vendor_firmware
	fi
else
	log "Skipping AP6330 WiFi firmware"
fi

sync
umount "$ROOT_MOUNT"
ROOT_MOUNT=""
losetup -d "$IMAGE_LOOP"
IMAGE_LOOP=""

if [ -n "$VENDOR_MOUNT" ] && mountpoint -q "$VENDOR_MOUNT"; then
	umount "$VENDOR_MOUNT"
fi
VENDOR_MOUNT=""
if [ -n "$VENDOR_LOOP" ]; then
	losetup -d "$VENDOR_LOOP"
	VENDOR_LOOP=""
fi

log "Done: $OUTPUT"

log ""
read -r -p "Write this image to an SD card? [y/N] " reply </dev/tty
case "$reply" in
	[yY]*)
		log ""
		log "Available disks (exclude the one with / mount):"
		lsblk -dno NAME,SIZE,MODEL,TRAN | grep -v loop
		log ""
		log "Enter the device path (e.g. /dev/sdb):"
		read -r sd_dev </dev/tty
		[ -b "$sd_dev" ] || die "not a block device: $sd_dev"
		log ""
		log "WARNING: This will DESTROY ALL DATA on $sd_dev"
		read -r -p "Are you sure? Type the device name to confirm ($(basename "$sd_dev")): " confirm </dev/tty
		[ "$confirm" = "$(basename "$sd_dev")" ] || die "confirmation mismatch, aborting"
		log "Writing $OUTPUT to $sd_dev ..."
		dd if="$OUTPUT" of="$sd_dev" bs=4M conv=sync status=progress
		sync
		log "Done. You can now remove the SD card."
		;;
esac
