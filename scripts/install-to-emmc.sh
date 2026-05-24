#!/usr/bin/env bash
set -euo pipefail

SELF="$(basename "$0")"

DRY_RUN=1
BACKUP_DIR=""
TARGET_EMMC="/dev/mmcblk1"
SOURCE_ROOT="/dev/mmcblk0p2"
MOUNTPOINT="/mnt/cb4-emmc-root"
ASSUME_YES=0

usage() {
	cat <<EOF
Usage:
  $SELF --backup-dir /path/on/usb [--execute]

Installs the currently running Cubieboard4 Debian 12 SD system to eMMC.

Default mode is dry-run. No destructive action is performed unless --execute is
passed and the confirmation prompt is answered with ERASE-EMMC.

Expected layout:
  source SD root:   /dev/mmcblk0p2
  target eMMC disk: /dev/mmcblk1
  target eMMC root: /dev/mmcblk1p2

The script intentionally does not write the raw eMMC bootloader area or
/dev/mmcblk1boot0/boot1. It preserves the existing eMMC bootloader and replaces
only the root filesystem partition.

Options:
  --backup-dir DIR   Directory where eMMC metadata/backups will be written.
                     For --execute this must live on a mounted USB drive.
  --execute          Actually format /dev/mmcblk1p2 and install to eMMC.
  --yes              Skip interactive prompt; requires --execute.
  --target DEV       Target eMMC disk, default: /dev/mmcblk1.
  --source-root DEV  Source root partition, default: /dev/mmcblk0p2.
  --mountpoint DIR   Temporary mountpoint, default: /mnt/cb4-emmc-root.
  -h, --help         Show this help.
EOF
}

log() {
	printf '%s\n' "$*"
}

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

run() {
	log "+ $*"
	if [ "$DRY_RUN" -eq 0 ]; then
		"$@"
	fi
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

resolve_source() {
	findmnt -n -o SOURCE /
}

partition_start() {
	local part="$1"
	local name
	name="$(basename "$part")"
	cat "/sys/class/block/$name/start"
}

partition_size() {
	local part="$1"
	local name
	name="$(basename "$part")"
	cat "/sys/class/block/$name/size"
}

dump_partition_layout() {
	local disk="$1"
	local out="$2"

	{
		echo "# $disk partition layout captured on $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
		echo "# lsblk"
		lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS "$disk" || true
		echo
		echo "# sysfs start/size"
		for part in "${disk}"p*; do
			[ -b "$part" ] || continue
			echo "$part start=$(partition_start "$part") size=$(partition_size "$part")"
		done
		echo
		echo "# blkid"
		blkid "$disk"* || true
	} >"$out"
}

mount_source_for_path() {
	findmnt -n -o SOURCE -T "$1"
}

mount_target_for_path() {
	findmnt -n -o TARGET -T "$1"
}

disk_for_block_device() {
	local dev="$1"
	local name
	local pkname

	name="$(basename "$dev")"
	pkname="$(lsblk -n -o PKNAME "$dev" 2>/dev/null | head -n 1 || true)"
	if [ -n "$pkname" ]; then
		printf '/dev/%s\n' "$pkname"
	else
		printf '/dev/%s\n' "$name"
	fi
}

transport_for_block_device() {
	local dev="$1"
	local disk

	disk="$(disk_for_block_device "$dev")"
	lsblk -n -o TRAN "$disk" 2>/dev/null | head -n 1
}

validate_backup_dir() {
	local dir="$1"
	local source
	local target
	local transport
	local available_kb
	local test_file

	source="$(mount_source_for_path "$dir")"
	target="$(mount_target_for_path "$dir")"
	transport=""
	if [ -b "$source" ]; then
		transport="$(transport_for_block_device "$source")"
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		log "Backup mount:       ${target:-unknown}"
		log "Backup source:      ${source:-unknown}"
		log "Backup transport:   ${transport:-unknown}"
		return
	fi

	[ -n "$source" ] || die "cannot determine backup filesystem for: $dir"
	[ "$target" != "/" ] || die "--backup-dir must be on an external USB drive, not the running root filesystem"
	[ "$target" != "/tmp" ] || die "--backup-dir must be persistent; /tmp is not acceptable"
	[ -b "$source" ] || die "--backup-dir is not on a block device: $source"
	[ "$transport" = "usb" ] || die "--backup-dir must be on a mounted USB drive; got source=$source transport=${transport:-unknown}"
	[ "$source" != "$SOURCE_ROOT" ] || die "--backup-dir cannot be on the source SD root"
	[ "$source" != "$TARGET_ROOT" ] || die "--backup-dir cannot be on the target eMMC root"

	available_kb="$(df -Pk "$dir" | awk 'NR == 2 {print $4}')"
	[ -n "$available_kb" ] || die "cannot determine free space for backup directory"
	[ "$available_kb" -ge 65536 ] || die "backup directory needs at least 64 MiB free"

	test_file="$dir/.cb4-emmc-backup-write-test"
	printf 'cb4 backup write test\n' >"$test_file" || die "backup directory write test failed"
	sync "$test_file" 2>/dev/null || sync
	rm -f "$test_file"
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--backup-dir)
			[ "$#" -ge 2 ] || die "--backup-dir requires a value"
			BACKUP_DIR="$2"
			shift 2
			;;
		--execute)
			DRY_RUN=0
			shift
			;;
		--yes)
			ASSUME_YES=1
			shift
			;;
		--target)
			[ "$#" -ge 2 ] || die "--target requires a value"
			TARGET_EMMC="$2"
			shift 2
			;;
		--source-root)
			[ "$#" -ge 2 ] || die "--source-root requires a value"
			SOURCE_ROOT="$2"
			shift 2
			;;
		--mountpoint)
			[ "$#" -ge 2 ] || die "--mountpoint requires a value"
			MOUNTPOINT="$2"
			shift 2
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

[ "$(id -u)" -eq 0 ] || die "run as root on the Cubieboard4"
[ "$(uname -s)" = "Linux" ] || die "this installer must run on Linux"

TARGET_ROOT="${TARGET_EMMC}p2"
TARGET_BOOT="${TARGET_EMMC}p1"

require_cmd findmnt
require_cmd lsblk
require_cmd blkid
require_cmd dd
require_cmd sha256sum
require_cmd mkfs.ext4
require_cmd mount
require_cmd umount
require_cmd mkimage
require_cmd tar

if command -v rsync >/dev/null 2>&1; then
	COPY_METHOD="rsync"
else
	COPY_METHOD="tar"
fi

[ -b "$SOURCE_ROOT" ] || die "source root partition not found: $SOURCE_ROOT"
[ -b "$TARGET_EMMC" ] || die "target eMMC disk not found: $TARGET_EMMC"
[ -b "$TARGET_ROOT" ] || die "target eMMC root partition not found: $TARGET_ROOT"
[ -b "$TARGET_BOOT" ] || die "target eMMC boot partition not found: $TARGET_BOOT"

CURRENT_ROOT="$(resolve_source)"
[ "$CURRENT_ROOT" = "$SOURCE_ROOT" ] || die "expected / to be mounted from $SOURCE_ROOT, got $CURRENT_ROOT"

[ -n "$BACKUP_DIR" ] || die "--backup-dir is required"
mkdir -p "$BACKUP_DIR"
[ -d "$BACKUP_DIR" ] || die "backup directory does not exist: $BACKUP_DIR"
[ -w "$BACKUP_DIR" ] || die "backup directory is not writable: $BACKUP_DIR"
validate_backup_dir "$BACKUP_DIR"

KERNEL_VERSION="$(uname -r)"
KERNEL_IMAGE="/boot/vmlinuz-${KERNEL_VERSION}"
INITRD_IMAGE="/boot/initrd.img-${KERNEL_VERSION}"
DTB_IMAGE="/boot/sun9i-a80-cubieboard4.dtb"

[ -f "$KERNEL_IMAGE" ] || die "kernel image not found: $KERNEL_IMAGE"
[ -f "$INITRD_IMAGE" ] || die "initrd image not found: $INITRD_IMAGE"
[ -f "$DTB_IMAGE" ] || die "validated DTB not found: $DTB_IMAGE"

if findmnt -n "$TARGET_ROOT" >/dev/null 2>&1; then
	die "$TARGET_ROOT is already mounted"
fi

cat <<EOF
Cubieboard4 eMMC installer

Current root:       $CURRENT_ROOT
Target eMMC disk:   $TARGET_EMMC
Target rootfs:      $TARGET_ROOT
Target boot part:   $TARGET_BOOT
Kernel:             $KERNEL_VERSION
Backup directory:   $BACKUP_DIR
Copy method:        $COPY_METHOD
Mode:               $([ "$DRY_RUN" -eq 1 ] && echo dry-run || echo execute)

This will preserve the raw eMMC bootloader area but will erase and replace:
  $TARGET_ROOT

It will not write:
  $TARGET_EMMC raw disk
  ${TARGET_EMMC}boot0
  ${TARGET_EMMC}boot1
EOF

if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
	printf '\nType ERASE-EMMC to continue: '
	read -r answer
	[ "$answer" = "ERASE-EMMC" ] || die "confirmation failed"
fi

BACKUP_PREFIX="$BACKUP_DIR/cb4-emmc-$(date -u '+%Y%m%d-%H%M%S')"

log
log "Capturing non-destructive eMMC backup metadata..."
run dd "if=$TARGET_EMMC" "of=${BACKUP_PREFIX}-first-32m.bin" bs=1M count=32 status=progress conv=fsync
if [ "$DRY_RUN" -eq 0 ]; then
	sha256sum "${BACKUP_PREFIX}-first-32m.bin" >"${BACKUP_PREFIX}-first-32m.sha256"
	dump_partition_layout "$TARGET_EMMC" "${BACKUP_PREFIX}-layout.txt"
else
	log "+ sha256sum ${BACKUP_PREFIX}-first-32m.bin >${BACKUP_PREFIX}-first-32m.sha256"
	log "+ dump partition layout >${BACKUP_PREFIX}-layout.txt"
fi

log
log "Formatting eMMC root partition..."
run mkfs.ext4 -F -L cb4-rootfs "$TARGET_ROOT"

log
log "Mounting target root..."
run mkdir -p "$MOUNTPOINT"
run mount "$TARGET_ROOT" "$MOUNTPOINT"

cleanup() {
	if [ "$DRY_RUN" -eq 0 ] && findmnt -n "$MOUNTPOINT" >/dev/null 2>&1; then
		umount "$MOUNTPOINT" || true
	fi
}
trap cleanup EXIT

log
log "Copying running SD rootfs to eMMC..."
if [ "$COPY_METHOD" = "rsync" ]; then
	run rsync -aHAX --numeric-ids \
		--exclude=/dev/* \
		--exclude=/proc/* \
		--exclude=/sys/* \
		--exclude=/run/* \
		--exclude=/tmp/* \
		--exclude=/mnt/* \
		--exclude=/media/* \
		--exclude=/lost+found \
		/ "$MOUNTPOINT/"
else
	log "+ tar copy / -> $MOUNTPOINT/"
	if [ "$DRY_RUN" -eq 0 ]; then
		tar --one-file-system \
			--exclude=./dev \
			--exclude=./proc \
			--exclude=./sys \
			--exclude=./run \
			--exclude=./tmp \
			--exclude=./mnt \
			--exclude=./media \
			--exclude=./lost+found \
			-cpf - -C / . | tar -xpf - -C "$MOUNTPOINT"
	fi
fi

log
log "Writing eMMC boot script..."
BOOT_CMD="$MOUNTPOINT/boot/boot.cmd"
if [ "$DRY_RUN" -eq 0 ]; then
	cat >"$BOOT_CMD" <<EOF
setenv devtype mmc
setenv devnum 1
load \${devtype} \${devnum}:\${distro_bootpart} \${kernel_addr_r} /boot/vmlinuz-${KERNEL_VERSION}
load \${devtype} \${devnum}:\${distro_bootpart} \${ramdisk_addr_r} /boot/initrd.img-${KERNEL_VERSION}
setenv ramdisk_size \${filesize}
setenv bootargs root=${TARGET_ROOT} rw rootwait
load \${devtype} \${devnum}:\${distro_bootpart} \${fdt_addr_r} /boot/sun9i-a80-cubieboard4.dtb
bootz \${kernel_addr_r} \${ramdisk_addr_r}:\${ramdisk_size} \${fdt_addr_r}
EOF
	mkimage -C none -A arm -T script -d "$BOOT_CMD" "$MOUNTPOINT/boot/boot.scr"
else
	log "+ write $BOOT_CMD for devnum 1 and root=$TARGET_ROOT"
	log "+ mkimage -C none -A arm -T script -d $BOOT_CMD $MOUNTPOINT/boot/boot.scr"
fi

log
log "Final verification..."
if [ "$DRY_RUN" -eq 0 ]; then
	test -f "$MOUNTPOINT/boot/vmlinuz-${KERNEL_VERSION}"
	test -f "$MOUNTPOINT/boot/initrd.img-${KERNEL_VERSION}"
	test -f "$MOUNTPOINT/boot/sun9i-a80-cubieboard4.dtb"
	test -f "$MOUNTPOINT/boot/boot.scr"
	sync
	umount "$MOUNTPOINT"
	trap - EXIT
fi

cat <<EOF

Done.

Next validation step:
  1. power off
  2. remove microSD
  3. boot from eMMC
  4. capture serial log

Expected eMMC boot root:
  $TARGET_ROOT
EOF
