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
			die "required command not found: $cmd (install with: apt install $pkg)"
		else
			die "required command not found: $cmd"
		fi
	fi
}

require_cmd blkid         util-linux
require_cmd curl
require_cmd gzip          gzip
require_cmd install       coreutils
require_cmd losetup       util-linux
require_cmd mkimage       u-boot-tools
require_cmd mount         mount
require_cmd mountpoint    mount
require_cmd sha256sum     coreutils
require_cmd sync          coreutils
require_cmd umount        mount

CACHE_DIR="$WORK_DIR/cache"
mkdir -p "$CACHE_DIR"

log "=== Cubieboard4 A80 Debian 12 SD Image Builder ==="
log ""

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
	read -r -p "Download missing assets? [Y/n] " reply
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

download_asset "$BOOT_ASSET"
download_asset "$ROOTFS_ASSET"
verify_sha256 "$CACHE_DIR/$BOOT_ASSET" "$BOOT_SHA256"
verify_sha256 "$CACHE_DIR/$ROOTFS_ASSET" "$ROOTFS_SHA256"

log "Building SD image: $OUTPUT"
rm -f "$OUTPUT"
gzip -dc "$CACHE_DIR/$BOOT_ASSET" >"$OUTPUT"
gzip -dc "$CACHE_DIR/$ROOTFS_ASSET" >>"$OUTPUT"
sync "$OUTPUT" 2>/dev/null || sync

IMAGE_LOOP="$(attach_loop "$OUTPUT")"
root_part="$(partition_path "$IMAGE_LOOP" 2)"
log "Mounting generated rootfs: $root_part"
mount "$root_part" "$ROOT_MOUNT"

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
