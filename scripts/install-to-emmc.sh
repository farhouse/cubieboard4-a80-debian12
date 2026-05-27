#!/usr/bin/env bash
set -euo pipefail

SELF="$(basename "$0")"

DRY_RUN=1
BACKUP_DIR=""
TARGET_EMMC=""
SOURCE_ROOT=""
MOUNTPOINT="/mnt/cb4-emmc-root"
ASSUME_YES=0
UBOOT_BIN="/boot/u-boot-sunxi-with-spl.bin"

usage() {
	cat <<EOF
Usage:
  $SELF --backup-dir /path/on/usb [--execute]

Installs the currently running Cubieboard4 Debian 12 SD system to eMMC.

Default mode is dry-run. No destructive action is performed unless --execute is
passed and the confirmation prompt is answered with ERASE-EMMC.

The script auto-detects the source SD root and target eMMC disk by scanning
MMC devices.

The script also flashes a rebuilt U-Boot to the main eMMC user area at
sector 16 (offset 8KB), which is where the A80 boot ROM reads it.

Options:
  --backup-dir DIR   Directory where eMMC metadata/backups will be written.
                     For --execute this must live on a mounted USB drive.
  --execute          Actually format eMMC root partition and install.
  --yes              Skip interactive prompt; requires --execute.
  --target DEV       Target eMMC disk (auto-detected if omitted).
  --source-root DEV  Source root partition (auto-detected if omitted).
  --mountpoint DIR   Temporary mountpoint, default: /mnt/cb4-emmc-root.
  --uboot-bin PATH   Path to u-boot-sunxi-with-spl.bin, default:
                     /boot/u-boot-sunxi-with-spl.bin.
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

missing_pkgs=""

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

resolve_source() {
	findmnt -n -o SOURCE /
}

# Detect the eMMC block device (non-removable MMC that isn't the SD source)
detect_emmc() {
	local source_disk="$1"
	local dev
	local disk
	local removable

	for dev in /dev/mmcblk*; do
		[ -b "$dev" ] || continue
		[ "${dev#/dev/mmcblk[0-9]}" != "$dev" ] && [ "$dev" = "${dev%p*}" ] || continue
		# Skip partitions, only check disks
		case "$(basename "$dev")" in
			mmcblk[0-9]) ;;
			*) continue ;;
		esac
		[ "$dev" = "$source_disk" ] && continue
		removable="$(cat "/sys/block/$(basename "$dev")/removable" 2>/dev/null || echo 1)"
		[ "$removable" = "0" ] || continue
		printf '%s\n' "$dev"
		return 0
	done

	# Fallback: find MMC device (type "MMC") not matching source
	for dev in /dev/mmcblk[0-9]; do
		[ -b "$dev" ] || continue
		[ "$dev" = "$source_disk" ] && continue
		local mmctype
		mmctype="$(cat "/sys/block/$(basename "$dev")/device/type" 2>/dev/null || true)"
		[ "$mmctype" = "MMC" ] || continue
		printf '%s\n' "$dev"
		return 0
	done

	return 1
}

# Resolve the disk device for a partition
disk_for_part() {
	local part="$1"
	local name
	local pkname
	name="$(basename "$part")"
	pkname="$(lsblk -n -o PKNAME "$part" 2>/dev/null | head -n1 || true)"
	[ -n "$pkname" ] && printf '/dev/%s\n' "$pkname" || return 1
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
		--uboot-bin)
			[ "$#" -ge 2 ] || die "--uboot-bin requires a value"
			UBOOT_BIN="$2"
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

require_cmd findmnt       util-linux
require_cmd lsblk         util-linux
require_cmd blkid         util-linux
require_cmd dd            coreutils
require_cmd sha256sum     coreutils
require_cmd mkfs.ext4     e2fsprogs
require_cmd mount         mount
require_cmd umount        mount
require_cmd mkimage       u-boot-tools
require_cmd tar           tar
require_cmd parted        parted

if [ -n "$missing_pkgs" ]; then
	log "Missing packages:$missing_pkgs"
	read -r -p "Install them with apt? [Y/n] " reply </dev/tty
	case "$reply" in
		[nN]*) die "install required packages manually: apt install$missing_pkgs" ;;
	esac
	apt update && apt install -y $missing_pkgs
fi

if command -v rsync >/dev/null 2>&1; then
	COPY_METHOD="rsync"
else
	COPY_METHOD="tar"
fi

# Resolve source root
if [ -z "$SOURCE_ROOT" ]; then
	SOURCE_ROOT="$(resolve_source)"
fi
[ -b "$SOURCE_ROOT" ] || die "source root partition not found: $SOURCE_ROOT"

CURRENT_ROOT="$(resolve_source)"
[ "$CURRENT_ROOT" = "$SOURCE_ROOT" ] || die "expected / to be mounted from $SOURCE_ROOT, got $CURRENT_ROOT"

SOURCE_DISK="$(disk_for_part "$SOURCE_ROOT")"
[ -n "$SOURCE_DISK" ] || die "cannot resolve source disk for: $SOURCE_ROOT"

# Resolve target eMMC
if [ -z "$TARGET_EMMC" ]; then
	TARGET_EMMC="$(detect_emmc "$SOURCE_DISK")"
	[ -n "$TARGET_EMMC" ] || die "cannot auto-detect eMMC device; specify --target manually"
fi
[ -b "$TARGET_EMMC" ] || die "target eMMC disk not found: $TARGET_EMMC"

TARGET_ROOT="${TARGET_EMMC}p2"
TARGET_BOOT="${TARGET_EMMC}p1"

[ -b "$TARGET_ROOT" ] || die "target eMMC root partition not found: $TARGET_ROOT"
[ -b "$TARGET_BOOT" ] || die "target eMMC boot partition not found: $TARGET_BOOT"

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
[ -f "$UBOOT_BIN" ] || die "U-Boot binary not found: $UBOOT_BIN"

if findmnt -n "$TARGET_ROOT" >/dev/null 2>&1; then
	die "$TARGET_ROOT is already mounted"
fi

cat <<EOF
Cubieboard4 eMMC installer

Current root:       $CURRENT_ROOT
Source disk:        $SOURCE_DISK
Target eMMC disk:   $TARGET_EMMC
Target rootfs:      $TARGET_ROOT
Target boot part:   $TARGET_BOOT
U-Boot binary:      $UBOOT_BIN
Kernel:             $KERNEL_VERSION
Backup directory:   $BACKUP_DIR
Copy method:        $COPY_METHOD
Mode:               $([ "$DRY_RUN" -eq 1 ] && echo dry-run || echo execute)

This will:
  - flash $UBOOT_BIN to $TARGET_EMMC at sector 16 (A80 boot ROM offset)
  - resize $TARGET_ROOT to fill the full eMMC
  - erase and replace $TARGET_ROOT
  - preserve $TARGET_BOOT (FAT partition)
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
log "Flashing U-Boot to $TARGET_EMMC at sector 16 (A80 boot ROM offset)..."
run dd "if=$UBOOT_BIN" "of=$TARGET_EMMC" bs=512 seek=16 conv=fsync

log
log "Resizing root partition to fill remaining eMMC space..."
TARGET_ROOT_PARTNO="${TARGET_ROOT##*p}"
EMMC_SIZE="$(cat "/sys/block/$(basename "$TARGET_EMMC")/size")"
TARGET_BOOT_START="$(cat "/sys/block/$(basename "$TARGET_BOOT")/start")"
TARGET_ROOT_START="$(cat "/sys/block/$(basename "$TARGET_ROOT")/start")"
# Align end to sector boundary (1 MiB = 2048 sectors)
ALIGN_SECTORS=2048
ROOT_END_SECTOR=$(( (EMMC_SIZE / ALIGN_SECTORS) * ALIGN_SECTORS - 1 ))
run parted -s "$TARGET_EMMC" "resizepart $TARGET_ROOT_PARTNO ${ROOT_END_SECTOR}s"
run partprobe "$TARGET_EMMC" 2>/dev/null || true

log
log "Formatting eMMC root partition..."
run mkfs.ext4 -F -E nodiscard -L cb4-rootfs "$TARGET_ROOT"

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
TARGET_ROOT_SPEC="UUID=<target-rootfs-uuid-after-format>"
if [ "$DRY_RUN" -eq 0 ]; then
	TARGET_ROOT_UUID="$(blkid -s UUID -o value "$TARGET_ROOT")"
	[ -n "$TARGET_ROOT_UUID" ] || die "cannot determine target root UUID for: $TARGET_ROOT"
	TARGET_ROOT_SPEC="UUID=$TARGET_ROOT_UUID"
	cat >"$BOOT_CMD" <<EOF
load \${devtype} \${devnum}:\${distro_bootpart} \${kernel_addr_r} /boot/vmlinuz-${KERNEL_VERSION}
load \${devtype} \${devnum}:\${distro_bootpart} \${ramdisk_addr_r} /boot/initrd.img-${KERNEL_VERSION}
setenv ramdisk_size \${filesize}
setenv bootargs root=${TARGET_ROOT_SPEC} rw rootwait
load \${devtype} \${devnum}:\${distro_bootpart} \${fdt_addr_r} /boot/sun9i-a80-cubieboard4.dtb
bootz \${kernel_addr_r} \${ramdisk_addr_r}:\${ramdisk_size} \${fdt_addr_r}
EOF
	mkimage -C none -A arm -T script -d "$BOOT_CMD" "$MOUNTPOINT/boot/boot.scr"
else
	log "+ write $BOOT_CMD (uses distro auto-discovered devnum/devtype) root=$TARGET_ROOT_SPEC"
	log "+ mkimage -C none -A arm -T script -d $BOOT_CMD $MOUNTPOINT/boot/boot.scr"
fi

log
log "Final verification..."
if [ "$DRY_RUN" -eq 0 ]; then
	dd "if=$TARGET_EMMC" bs=4 skip=16 count=1 2>/dev/null | grep -q 'eGON' || die "U-Boot flash verification failed: eGON signature not found at sector 16 of $TARGET_EMMC"
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
  $TARGET_ROOT_SPEC

U-Boot flashed at sector 16 with the get_mclk_offset fix
(CONFIG_MACH_SUN9I instead of CONFIG_MACH_SUN9I_A80).
See notes/2026-05-26-emmc-boot-fix-clock-register.md for details.
EOF
