#!/usr/bin/env bash
# install-to-emmc.sh — Interactive wizard for SD→eMMC install on Cubieboard4 A80
set -euo pipefail

# ── Config ────────────────────────────────────────────────────
SELF="$(basename "$0")"
MOUNTPOINT="/mnt/cb4-emmc-root"
UBOOT_BIN_DEFAULT="/boot/u-boot-sunxi-with-spl.bin"
LOGFILE="/tmp/install-to-emmc-$(date -u '+%Y%m%d-%H%M%S').log"

# ── Helpers ────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

die()   { printf "\n${RED}✖ ERROR: %s${NC}\n" "$*" >&2; exit 1; }
step()  { printf "\n${CYAN}════════════════════════════════════════════════${NC}\n${BOLD}%s${NC}\n" "$*"; }
info()  { printf "  %s\n" "$*"; }
ok()    { printf "  ${GREEN}✔ %s${NC}\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠ %s${NC}\n" "$*"; }
log()   { printf "[%s] %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOGFILE"; }
sep()   { printf "  ${CYAN}────────────────────────────────────────────${NC}\n"; }

prompt_yn() {
	[ "${AUTO_YES:-0}" -eq 1 ] && return 0
	local prompt="$1 [Y/n] " reply
	read -r -p "$prompt" reply </dev/tty
	case "$reply" in [nN]*) return 1;; *) return 0;; esac
}

prompt_confirm() {
	local prompt="$1" reply
	read -r -p "${BOLD}${prompt}${NC} " reply </dev/tty
	[ "$reply" = "$2" ] || die "confirmation failed (expected '$2')"
}

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		missing="$missing $2"
	fi
}

show_progress() {
	local desc="$1" pid=$2
	while kill -0 "$pid" 2>/dev/null; do
		printf "\r  ${desc}..."
		sleep 1
	done
	wait "$pid" && printf "\r  ${GREEN}✔${NC} ${desc}  \n" || return 1
}

# ── Prerequisites ──────────────────────────────────────────────
check_prereqs() {
	step "Prerequisites"
	missing=""
	require_cmd findmnt       util-linux
	require_cmd lsblk         util-linux
	require_cmd blkid         util-linux
	require_cmd dd            coreutils
	require_cmd sha256sum     coreutils
	require_cmd strings       binutils
	require_cmd mkfs.ext4     e2fsprogs
	require_cmd mkfs.vfat     dosfstools
	require_cmd mount         mount
	require_cmd umount        mount
	require_cmd mkimage       u-boot-tools
	require_cmd parted        parted
	require_cmd rsync         rsync

	if [ -z "$missing" ]; then
		ok "all required packages present"
		return 0
	fi

	warn "Missing packages:$missing"
	if prompt_yn "Install them with apt?"; then
		apt update && apt install -y $missing || die "package install failed"
		ok "packages installed"
	else
		die "install required packages: apt install$missing"
	fi
}

root_check() {
	[ "$(id -u)" -eq 0 ] || die "run as root"
	[ "$(uname -s)" = "Linux" ] || die "this script must run on Linux"
}

# ── Detection ──────────────────────────────────────────────────
detect_hardware() {
	step "Hardware Detection"

	SOURCE_ROOT="$(findmnt -n -o SOURCE /)"
	SOURCE_DISK="$(lsblk -n -o PKNAME "$SOURCE_ROOT" 2>/dev/null | head -1)"
	[ -n "$SOURCE_DISK" ] && SOURCE_DISK="/dev/$SOURCE_DISK"
	[ -b "$SOURCE_ROOT" ] || die "source root not found: $SOURCE_ROOT"

	info "Source root:  $SOURCE_ROOT  ($(lsblk -dno SIZE "$SOURCE_ROOT" 2>/dev/null))"

	if [ -b "$SOURCE_DISK" ]; then
		# Check MMC device type first (more reliable than removable flag,
		# since some SD slots report removable=0 on this board).
		SRC_SYS="/sys/block/$(basename "$SOURCE_DISK")"
		MMC_TYPE="$(cat "$SRC_SYS/device/type" 2>/dev/null || true)"
		REMOVABLE="$(cat "$SRC_SYS/removable" 2>/dev/null || true)"
		if [ "$MMC_TYPE" = "MMC" ]; then
			SOURCE_TYPE="eMMC"
		elif [ "$REMOVABLE" = "1" ]; then
			SOURCE_TYPE="SD"
		else
			# Fallback: if there's another non-removable mmcblk, source is likely SD
			if grep -l '0' /sys/block/mmcblk*/removable 2>/dev/null | grep -v "$(basename "$SOURCE_DISK")" | head -1 >/dev/null; then
				SOURCE_TYPE="SD (probably)"
			else
				SOURCE_TYPE="unknown"
			fi
		fi
		info "Source disk:  $SOURCE_DISK  (${SOURCE_TYPE})"
	fi

	# Detect eMMC
	TARGET_EMMC=""
	for dev in /dev/mmcblk[0-9] /dev/mmcblk[0-9][0-9]; do
		[ -b "$dev" ] || continue
		[ "$dev" = "$SOURCE_DISK" ] && continue
		removable="$(cat "/sys/block/$(basename "$dev")/removable" 2>/dev/null || echo 1)"
		[ "$removable" = "0" ] || continue
		TARGET_EMMC="$dev"
		break
	done

	if [ -z "$TARGET_EMMC" ]; then
		for dev in /dev/mmcblk[0-9] /dev/mmcblk[0-9][0-9]; do
			[ -b "$dev" ] || continue
			[ "$dev" = "$SOURCE_DISK" ] && continue
			mmctype="$(cat "/sys/block/$(basename "$dev")/device/type" 2>/dev/null || true)"
			[ "$mmctype" = "MMC" ] || continue
			TARGET_EMMC="$dev"
			break
		done
	fi

	if [ -z "$TARGET_EMMC" ]; then
		warn "No eMMC detected automatically"
		read -r -p "Enter eMMC device path (e.g. /dev/mmcblk1): " TARGET_EMMC </dev/tty
		[ -b "$TARGET_EMMC" ] || die "invalid device: $TARGET_EMMC"
	fi

	EMMC_SIZE="$(cat "/sys/block/$(basename "$TARGET_EMMC")/size" 2>/dev/null)"
	EMMC_HUMAN="$(lsblk -dno SIZE "$TARGET_EMMC" 2>/dev/null || echo "${EMMC_SIZE} sectors")"
	TARGET_ROOT="${TARGET_EMMC}p2"
	TARGET_BOOT="${TARGET_EMMC}p1"

	info "Target eMMC: $TARGET_EMMC  ($EMMC_HUMAN)"
	info "Boot part:   $TARGET_BOOT"
	info "Root part:   $TARGET_ROOT"

	if [ ! -b "$TARGET_ROOT" ] || [ ! -b "$TARGET_BOOT" ]; then
		warn "eMMC partition layout not found"
		lsblk "$TARGET_EMMC" 2>/dev/null || true
		return 1
	fi

	if ! prompt_yn "Is this correct?"; then
		read -r -p "Enter eMMC device (e.g. /dev/mmcblk1): " TARGET_EMMC </dev/tty
		[ -b "$TARGET_EMMC" ] || die "invalid device: $TARGET_EMMC"
		TARGET_ROOT="${TARGET_EMMC}p2"
		TARGET_BOOT="${TARGET_EMMC}p1"
		EMMC_SIZE="$(cat "/sys/block/$(basename "$TARGET_EMMC")/size" 2>/dev/null || echo 0)"
		info "Updated target: $TARGET_EMMC"
	fi

	ok "hardware detected"
	return 0
}

# ── Detect kernel/boot assets ──────────────────────────────────
detect_assets() {
	step "Boot Assets"

	KERNEL_VERSION="$(uname -r)"
	KERNEL_IMAGE="/boot/vmlinuz-${KERNEL_VERSION}"
	INITRD_IMAGE="/boot/initrd.img-${KERNEL_VERSION}"
	DTB_IMAGE=""
	UBOOT_BIN="$UBOOT_BIN_DEFAULT"

	# Search for DTB
	for dtb_candidate in \
		"/boot/sun9i-a80-cubieboard4.dtb" \
		"/boot/dtb-${KERNEL_VERSION}/sun9i-a80-cubieboard4.dtb" \
		"/usr/lib/linux-image-${KERNEL_VERSION}/sun9i-a80-cubieboard4.dtb" \
		"/usr/lib/linux-image-${KERNEL_VERSION}/allwinner/sun9i-a80-cubieboard4.dtb"; do
		if [ -f "$dtb_candidate" ]; then
			DTB_IMAGE="$dtb_candidate"
			break
		fi
	done

	info "Kernel: $KERNEL_VERSION"

	if [ ! -f "$KERNEL_IMAGE" ]; then
		# Try wildcard
		KERNEL_IMAGE="$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 || true)"
		[ -n "$KERNEL_IMAGE" ] || die "no kernel found in /boot"
		KERNEL_VERSION="${KERNEL_IMAGE#/boot/vmlinuz-}"
		INITRD_IMAGE="/boot/initrd.img-${KERNEL_VERSION}"
		info "Found kernel: $KERNEL_VERSION"
	fi

	[ -f "$KERNEL_IMAGE" ] || die "kernel not found: $KERNEL_IMAGE"
	[ -f "$INITRD_IMAGE" ] || warn "initrd not found: $INITRD_IMAGE"
	[ -n "$DTB_IMAGE" ]  || warn "DTB not found (will use installed DTB if available)"
	[ -f "$UBOOT_BIN" ]  || warn "U-Boot binary not found at $UBOOT_BIN"

	if [ -f "$KERNEL_IMAGE" ]; then ok "kernel: ${KERNEL_IMAGE##*/}"; fi
	if [ -f "$INITRD_IMAGE" ]; then ok "initrd: ${INITRD_IMAGE##*/}"; fi
	if [ -n "$DTB_IMAGE" ]; then ok "DTB: ${DTB_IMAGE##*/}"; fi
	if [ -f "$UBOOT_BIN" ]; then ok "U-Boot: ${UBOOT_BIN##*/} ($(stat -c%s "$UBOOT_BIN" 2>/dev/null) bytes)"; fi
}

# ── Repartition eMMC ──────────────────────────────────────────
repartition_emmc() {
	step "Partition eMMC"
	warn "This will DESTROY all data on $TARGET_EMMC"

	echo ""
	lsblk "$TARGET_EMMC" 2>/dev/null || true
	echo ""

	prompt_confirm "Type REPARTITION to continue:" "REPARTITION"

	# Calculate sizes
	TOTAL_SECTORS="$EMMC_SIZE"

	# boot partition: 128 MiB
	BOOT_SIZE_MiB=128
	BOOT_SECTORS=$((BOOT_SIZE_MiB * 1024 * 1024 / 512))

	# Align to 1 MiB
	ALIGN=2048  # sectors
	START_SECTOR=$ALIGN
	BOOT_END=$((START_SECTOR + BOOT_SECTORS - 1))

	# Root partition: rest, aligned
	ROOT_START=$(( (BOOT_END + ALIGN) / ALIGN * ALIGN ))
	ROOT_END=$(( (TOTAL_SECTORS / ALIGN) * ALIGN - 1 ))

	info "Layout:"
	info "  p1: ${BOOT_SIZE_MiB}MiB FAT (${START_SECTOR}s → ${BOOT_END}s)"
	info "  p2: $(( (ROOT_END - ROOT_START + 1) * 512 / 1024 / 1024 ))MiB ext4 (${ROOT_START}s → ${ROOT_END}s)"

	if prompt_yn "Proceed with partitioning?"; then
		dd "if=/dev/zero" "of=$TARGET_EMMC" bs=1M count=4 conv=fsync 2>/dev/null || true
		parted -s "$TARGET_EMMC" mklabel msdos \
			"mkpart primary fat32 ${START_SECTOR}s ${BOOT_END}s" \
			"mkpart primary ext4 ${ROOT_START}s ${ROOT_END}s" || die "partitioning failed"

		partprobe "$TARGET_EMMC" 2>/dev/null || true
		sleep 1

		# Re-detect partitions
		partprobe "$TARGET_EMMC" 2>/dev/null || udevadm settle 2>/dev/null || true
		sleep 1

		# Format boot partition
		info "Formatting boot partition..."
		mkfs.vfat -F 32 -n CB4-BOOT "${TARGET_EMMC}p1" || die "boot format failed"
		ok "boot partition formatted"

		ok "repartitioning complete"
	else
		warn "repartitioning skipped"
	fi
}

# ── Backup ─────────────────────────────────────────────────────
backup_emmc() {
	step "Backup eMMC"
	BACKUP_DIR=""

	if [ ! -b "$TARGET_EMMC" ]; then
		warn "eMMC not available, skipping backup"
		return
	fi

	if ! prompt_yn "Backup eMMC before modifying?"; then
		info "backup skipped"
		return
	fi

	# Discover USB drives
	USB_DRIVES=()
	while IFS= read -r line; do
		USB_DRIVES+=("$line")
	done < <(lsblk -dno NAME,SIZE,MODEL,TRAN 2>/dev/null | grep -i '\busb\b' || true)

	if [ ${#USB_DRIVES[@]} -gt 0 ]; then
		echo ""
		info "Available USB drives:"
		sep
		for i in "${!USB_DRIVES[@]}"; do
			printf "  %d) /dev/%s\n" $((i+1)) "${USB_DRIVES[i]}"
		done
		sep
		echo ""
		read -r -p "Select drive number (or press Enter for custom path): " reply </dev/tty

		if [ -n "$reply" ] && [ "$reply" -eq "$reply" ] 2>/dev/null; then
			idx=$((reply-1))
			[ "$idx" -ge 0 ] && [ "$idx" -lt "${#USB_DRIVES[@]}" ] || die "invalid selection"
			USB_DEV="/dev/$(echo "${USB_DRIVES[idx]}" | awk '{print $1}')"
			USB_PART="$(lsblk -nlo NAME "${USB_DEV}" 2>/dev/null | grep -v "^$(basename "$USB_DEV")\$" | head -1)"
			if [ -n "$USB_PART" ]; then
				USB_MOUNT="/mnt/cb4-usb-backup"
				mkdir -p "$USB_MOUNT"
				mount "/dev/$USB_PART" "$USB_MOUNT" 2>/dev/null || mount "$USB_DEV" "$USB_MOUNT" 2>/dev/null || {
					warn "cannot mount $USB_DEV"
					read -r -p "Enter backup directory path: " reply </dev/tty
					[ -d "$reply" ] && BACKUP_DIR="$reply"
					return
				}
				BACKUP_DIR="$USB_MOUNT/cb4-emmc-backup-$(date -u '+%Y%m%d-%H%M%S')"
				mkdir -p "$BACKUP_DIR"
				info "Backup directory: $BACKUP_DIR"
			fi
		elif [ -n "$reply" ] && [ -d "$reply" ]; then
			BACKUP_DIR="$reply"
		fi
	else
		info "No USB drives detected"
		read -r -p "Enter backup directory path (or empty to skip): " reply </dev/tty
		[ -n "$reply" ] && [ -d "$reply" ] && BACKUP_DIR="$reply"
	fi

	if [ -z "$BACKUP_DIR" ]; then
		warn "no backup target available"
		return
	fi

	# Verify backup is not on SD or eMMC
	BACKUP_DEV="$(findmnt -n -o SOURCE "$BACKUP_DIR" 2>/dev/null || df "$BACKUP_DIR" 2>/dev/null | tail -1 | awk '{print $1}' || true)"
	if [ -n "$BACKUP_DEV" ]; then
		case "$BACKUP_DEV" in
			"*mmcblk*") warn "Backup target is on MMC (same device as eMMC/SD)! Choose another drive."; BACKUP_DIR=""; return ;;
		esac
	fi

	info "Backing up first 32 MiB of eMMC..."
	(
		dd "if=$TARGET_EMMC" "of=${BACKUP_DIR}/cb4-emmc-first-32m.bin" bs=1M count=32 status=none conv=fsync
		sha256sum "${BACKUP_DIR}/cb4-emmc-first-32m.bin" > "${BACKUP_DIR}/cb4-emmc-first-32m.sha256"
		{
			echo "# $TARGET_EMMC layout $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
			lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS "$TARGET_EMMC" 2>/dev/null || true
			blkid "$TARGET_EMMC"* 2>/dev/null || true
		} > "${BACKUP_DIR}/cb4-emmc-layout.txt"
	) &
	show_progress "Backing up eMMC" $!
	ok "backup saved to ${BACKUP_DIR}/"
}

# ── Flash U-Boot ──────────────────────────────────────────────
flash_uboot() {
	step "Flash U-Boot"

	if [ ! -f "$UBOOT_BIN" ]; then
		warn "U-Boot binary not found: $UBOOT_BIN"
		read -r -p "Enter path to u-boot-sunxi-with-spl.bin (or empty to skip): " reply </dev/tty
		[ -z "$reply" ] && { warn "skipping U-Boot flash"; return; }
		UBOOT_BIN="$reply"
		[ -f "$UBOOT_BIN" ] || die "file not found: $UBOOT_BIN"
	fi

	if [ ! -b "$TARGET_EMMC" ]; then
		die "eMMC not found: $TARGET_EMMC"
	fi

	info "Binary: $UBOOT_BIN ($(stat -c%s "$UBOOT_BIN" 2>/dev/null) bytes)"
	info "Target: $TARGET_EMMC sector 16"

	prompt_confirm "Type FLASH to continue:" "FLASH"

	dd "if=$UBOOT_BIN" "of=$TARGET_EMMC" bs=512 seek=16 conv=fsync

	# Verify
	MAGIC="$(dd "if=$TARGET_EMMC" bs=4 skip=16 count=1 2>/dev/null | strings | head -1)"
	sync
	if echo "$MAGIC" | grep -q 'eGON'; then
		ok "U-Boot flashed successfully (magic: $MAGIC)"
	else
		warn "U-Boot magic not found (got: '$MAGIC')"
	fi
}

# ── Format rootfs ─────────────────────────────────────────────
format_rootfs() {
	step "Format Root Partition"

	if [ ! -b "$TARGET_ROOT" ]; then
		die "root partition not found: $TARGET_ROOT"
	fi

	if findmnt -n "$TARGET_ROOT" >/dev/null 2>&1; then
		warn "$TARGET_ROOT is currently mounted!"
		prompt_confirm "Type FORCE to unmount and format:" "FORCE"
		umount "$TARGET_ROOT" 2>/dev/null || true
	fi

	ROOT_SIZE="$(lsblk -dno SIZE "$TARGET_ROOT" 2>/dev/null || echo "?")"
	info "Target: $TARGET_ROOT ($ROOT_SIZE)"

	warn "This will ERASE all data on $TARGET_ROOT"
	if ! prompt_yn "Format?"; then
		warn "formatting skipped"
		return 1
	fi

	mkfs.ext4 -F -E nodiscard -L cb4-rootfs "$TARGET_ROOT" 2>&1
	ok "root partition formatted"
}

# ── Copy rootfs ───────────────────────────────────────────────
copy_rootfs() {
	step "Copy Root Filesystem"

	if [ ! -b "$TARGET_ROOT" ]; then
		die "root partition not found: $TARGET_ROOT"
	fi

	if findmnt -n "$TARGET_ROOT" >/dev/null 2>&1; then
		warn "$TARGET_ROOT is already mounted at $(findmnt -n -o TARGET "$TARGET_ROOT")"
	else
		mkdir -p "$MOUNTPOINT"
		mount "$TARGET_ROOT" "$MOUNTPOINT"
	fi

	ROOT_MOUNT="$(findmnt -n -o TARGET "$TARGET_ROOT")"
	info "Target mount: $ROOT_MOUNT"

	# Check available space
	AVAIL="$(df -B1 --output=avail "$SOURCE_ROOT" 2>/dev/null | tail -1 || echo 0)"
	TARGET_AVAIL="$(df -B1 --output=avail "$ROOT_MOUNT" 2>/dev/null | tail -1 || echo 0)"
	SOURCE_USED="$(df -B1 --output=used "$SOURCE_ROOT" 2>/dev/null | tail -1 || echo 1)"

	info "Source used:  $(( SOURCE_USED / 1024 / 1024 )) MiB"
	info "Target avail: $(( TARGET_AVAIL / 1024 / 1024 )) MiB"

	if [ "$SOURCE_USED" -gt "$TARGET_AVAIL" ]; then
		warn "Target has less space than source used. This may fail!"
		if ! prompt_yn "Continue anyway?"; then
			umount "$ROOT_MOUNT" 2>/dev/null || true
			return
		fi
	fi

	if prompt_yn "Start copying?"; then
		echo ""
		rsync -aHAX --numeric-ids --info=progress2 \
			--exclude=/dev/* \
			--exclude=/proc/* \
			--exclude=/sys/* \
			--exclude=/run/* \
			--exclude=/tmp/* \
			--exclude=/mnt/* \
			--exclude=/media/* \
			--exclude=/root/install-to-emmc.sh \
			--exclude=/root/wifi-wizard.sh \
			--exclude=/lost+found \
			/ "$ROOT_MOUNT/"
		echo ""
		ok "root filesystem copied"
	else
		warn "copy skipped"
		umount "$ROOT_MOUNT" 2>/dev/null || true
		return 1
	fi
}

# ── Generate boot configuration ────────────────────────────────
configure_boot() {
	step "Configure Boot"

	ROOT_MOUNT="$(findmnt -n -o TARGET "$TARGET_ROOT" 2>/dev/null || true)"
	if [ -z "$ROOT_MOUNT" ]; then
		if [ ! -b "$TARGET_ROOT" ]; then
			die "root partition not found: $TARGET_ROOT"
		fi
		mkdir -p "$MOUNTPOINT"
		mount "$TARGET_ROOT" "$MOUNTPOINT"
		ROOT_MOUNT="$MOUNTPOINT"
	fi

	info "Target mount: $ROOT_MOUNT"
	info "Target root device: $TARGET_ROOT"

	TARGET_ROOT_UUID="$(blkid -s UUID -o value "$TARGET_ROOT")"
	if [ -z "$TARGET_ROOT_UUID" ]; then
		die "cannot determine UUID for $TARGET_ROOT"
	fi
	info "Root UUID: $TARGET_ROOT_UUID"

	# Resolve actual kernel version on target
	TARGET_KERNEL_VERSION="$KERNEL_VERSION"
	if [ -d "$ROOT_MOUNT/boot" ]; then
		TARGET_VMLINUZ="$(ls "$ROOT_MOUNT/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 || true)"
		if [ -n "$TARGET_VMLINUZ" ]; then
			TARGET_KERNEL_VERSION="${TARGET_VMLINUZ##*/vmlinuz-}"
			[ -f "$ROOT_MOUNT/boot/initrd.img-${TARGET_KERNEL_VERSION}" ] || {
				# Try to generate initrd
				warn "initrd not found for $TARGET_KERNEL_VERSION on target"
			}
		fi
	fi

	# Find DTB on target
	DTB_TARGET=""
	for d in "$ROOT_MOUNT/boot/sun9i-a80-cubieboard4.dtb" \
	         "$ROOT_MOUNT/boot/dtb-${TARGET_KERNEL_VERSION}/sun9i-a80-cubieboard4.dtb" \
	         "$ROOT_MOUNT/usr/lib/linux-image-${TARGET_KERNEL_VERSION}/sun9i-a80-cubieboard4.dtb" \
	         "$ROOT_MOUNT/usr/lib/linux-image-${TARGET_KERNEL_VERSION}/allwinner/sun9i-a80-cubieboard4.dtb"; do
		if [ -f "$d" ]; then
			DTB_TARGET="$d"
			break
		fi
	done

	# Copy DTB if we have one but target doesn't
	if [ -z "$DTB_TARGET" ] && [ -f "$DTB_IMAGE" ]; then
		mkdir -p "$ROOT_MOUNT/boot"
		cp "$DTB_IMAGE" "$ROOT_MOUNT/boot/sun9i-a80-cubieboard4.dtb"
		DTB_TARGET="$ROOT_MOUNT/boot/sun9i-a80-cubieboard4.dtb"
		info "copied DTB to target /boot/"
	elif [ -z "$DTB_TARGET" ]; then
		warn "no DTB found on target"
	fi

	# Copy U-Boot if we have it
	if [ -f "$UBOOT_BIN" ]; then
		mkdir -p "$ROOT_MOUNT/usr/lib/u-boot" 2>/dev/null || true
		if [ ! -f "$ROOT_MOUNT/usr/lib/u-boot/u-boot-sunxi-with-spl.bin" ]; then
			mkdir -p "$ROOT_MOUNT/usr/lib/u-boot"
			cp "$UBOOT_BIN" "$ROOT_MOUNT/usr/lib/u-boot/"
			info "copied U-Boot binary to target"
		fi
	fi

	# Detect boot.cmd path
	BOOT_CMD_PATH="$ROOT_MOUNT/boot/boot.cmd"

	# Generate boot.cmd
	info "Generating boot.cmd..."

	if [ -z "$DTB_TARGET" ]; then
		warn "No DTB, boot.scr will be generated without fdt_addr_r line"
	fi

	cat > "$BOOT_CMD_PATH" <<BOOTCMD
setenv devtype mmc
load \${devtype} \${devnum}:\${distro_bootpart} \${kernel_addr_r} /boot/vmlinuz-${TARGET_KERNEL_VERSION}
load \${devtype} \${devnum}:\${distro_bootpart} \${ramdisk_addr_r} /boot/initrd.img-${TARGET_KERNEL_VERSION}
setenv ramdisk_size \${filesize}
setenv bootargs root=UUID=${TARGET_ROOT_UUID} rw rootwait
load \${devtype} \${devnum}:\${distro_bootpart} \${fdt_addr_r} /boot/sun9i-a80-cubieboard4.dtb
bootz \${kernel_addr_r} \${ramdisk_addr_r}:\${ramdisk_size} \${fdt_addr_r}
BOOTCMD

	mkimage -C none -A arm -T script -d "$BOOT_CMD_PATH" "$ROOT_MOUNT/boot/boot.scr" 2>&1
	ok "boot.scr generated for UUID=$TARGET_ROOT_UUID kernel=$TARGET_KERNEL_VERSION"

	# Update fstab
	info "Updating /etc/fstab..."
	TARGET_BOOT_UUID="$(blkid -s UUID -o value "$TARGET_BOOT" 2>/dev/null || true)"
	cat > "$ROOT_MOUNT/etc/fstab" <<FSTAB
# /etc/fstab: static file system information.
UUID=$TARGET_ROOT_UUID / ext4 defaults,noatime 0 1
FSTAB
	if [ -n "$TARGET_BOOT_UUID" ]; then
		printf 'UUID=%s /boot vfat defaults 0 2\n' "$TARGET_BOOT_UUID" >> "$ROOT_MOUNT/etc/fstab"
		info "boot partition added to fstab"
	fi
	ok "/etc/fstab updated"

	# Copy boot files to FAT as fallback
	if [ -b "$TARGET_BOOT" ]; then
		FAT_MOUNT="$(mktemp -d 2>/dev/null || echo "/tmp/cb4-fat-mount")"
		mkdir -p "$FAT_MOUNT" 2>/dev/null || true
		if mount "$TARGET_BOOT" "$FAT_MOUNT" 2>/dev/null; then
			info "Copying boot files to FAT partition (fallback)..."
			cp "$ROOT_MOUNT/boot/boot.scr" "$ROOT_MOUNT/boot/boot.cmd" "$FAT_MOUNT/" 2>/dev/null || true
			mkdir -p "$FAT_MOUNT/boot"
			if [ -f "$ROOT_MOUNT/boot/vmlinuz-${TARGET_KERNEL_VERSION}" ]; then
				cp "$ROOT_MOUNT/boot/vmlinuz-${TARGET_KERNEL_VERSION}" "$FAT_MOUNT/boot/" 2>/dev/null || true
			fi
			if [ -f "$ROOT_MOUNT/boot/initrd.img-${TARGET_KERNEL_VERSION}" ]; then
				cp "$ROOT_MOUNT/boot/initrd.img-${TARGET_KERNEL_VERSION}" "$FAT_MOUNT/boot/" 2>/dev/null || true
			fi
			if [ -f "$DTB_TARGET" ]; then
				cp "$DTB_TARGET" "$FAT_MOUNT/boot/" 2>/dev/null || true
			fi
			sync
			umount "$FAT_MOUNT" 2>/dev/null || true
			rm -rf "$FAT_MOUNT" 2>/dev/null || true
			ok "FAT partition populated"
		else
			warn "could not mount $TARGET_BOOT (FAT fallback skipped)"
		fi
	fi

	# Sync and cleanup
	sync

	# Unmount if we mounted it
	if [ "$ROOT_MOUNT" = "$MOUNTPOINT" ]; then
		umount "$ROOT_MOUNT" 2>/dev/null || true
	fi
}

# ── Verification ────────────────────────────────────────────────
verify_install() {
	step "Verification"

	local errors=0

	if [ -b "$TARGET_EMMC" ]; then
		MAGIC="$(dd "if=$TARGET_EMMC" bs=4 skip=16 count=1 2>/dev/null | strings | head -1)"
		if echo "$MAGIC" | grep -q 'eGON'; then
			ok "U-Boot present at sector 16 (magic: $MAGIC)"
		else
			warn "U-Boot magic check: got '$MAGIC' (expected 'eGON...')"
			errors=$((errors + 1))
		fi
	else
		warn "eMMC not available for verification"
		errors=$((errors + 1))
	fi

	if [ -b "$TARGET_ROOT" ]; then
		if findmnt -n "$TARGET_ROOT" >/dev/null 2>&1; then
			ROOT_MOUNT="$(findmnt -n -o TARGET "$TARGET_ROOT")"

			for f in "vmlinuz-${KERNEL_VERSION}" "initrd.img-${KERNEL_VERSION}" "sun9i-a80-cubieboard4.dtb" "boot.scr"; do
				if [ -f "$ROOT_MOUNT/boot/$f" ]; then
					ok "rootfs:/boot/$f present"
				else
					warn "rootfs:/boot/$f missing"
					errors=$((errors + 1))
				fi
			done

			# Check fstab
			if grep -q "UUID=" "$ROOT_MOUNT/etc/fstab" 2>/dev/null; then
				ok "rootfs:/etc/fstab has UUID entry"
			else
				warn "rootfs:/etc/fstab missing UUID entry"
				errors=$((errors + 1))
			fi
		else
			warn "$TARGET_ROOT not mounted, mounting temporarily"
			mkdir -p "$MOUNTPOINT"
			if mount "$TARGET_ROOT" "$MOUNTPOINT" 2>/dev/null; then
				for f in "vmlinuz-*" "initrd.img-*" "sun9i-a80-cubieboard4.dtb" "boot.scr"; do
					ls "$MOUNTPOINT/boot/$f" >/dev/null 2>&1 && ok "rootfs:/boot/$f" || warn "rootfs:/boot/$f missing"
				done
				umount "$MOUNTPOINT" 2>/dev/null || true
			fi
		fi
	else
		warn "$TARGET_ROOT not found"
		errors=$((errors + 1))
	fi

	if [ "$errors" -eq 0 ]; then
		ok "All checks passed"
	else
		warn "$errors check(s) failed"
	fi
}

# ── Main Menu ──────────────────────────────────────────────────
main_menu() {
	clear
	cat <<WELCOME
${BOLD}╔══════════════════════════════════════════════════════════╗
║     Cubieboard4 A80 — SD → eMMC Installer (Wizard)     ║
╚══════════════════════════════════════════════════════════╝${NC}

This wizard will guide you through installing your running
SD system to the internal eMMC, step by step.

Each step can be skipped if already completed.

WELCOME

	if [ -f "$LOGFILE" ]; then
		info "Log: $LOGFILE"
		info "Resuming previous session detected"
		echo ""
	fi

	if prompt_yn "Begin?"; then
		log "=== Session started ==="
		return 0
	else
		die "exiting"
	fi
}

# ── Step selection menu ────────────────────────────────────────
select_steps() {
	step "Step Selection"
	info "Choose which steps to run:"
	sep

	steps=(
		"Check prerequisites"
		"Detect hardware"
		"Detect boot assets"
		"Repartition eMMC"
		"Backup eMMC"
		"Flash U-Boot"
		"Format root partition"
		"Copy root filesystem"
		"Configure boot"
		"Verify installation"
	)

	# All enabled by default
	run_step=()
	for i in "${!steps[@]}"; do
		printf "  %2d) %s\n" $((i+1)) "${steps[i]}"
		run_step[i]=1
	done
	sep
	echo ""

	read -r -p "Enter step numbers to SKIP (e.g. '1 4 5'), or press Enter for all: " reply </dev/tty
	if [ -n "$reply" ]; then
		for num in $reply; do
			idx=$((num-1))
			[ "$idx" -ge 0 ] && [ "$idx" -lt "${#steps[@]}" ] && run_step[idx]=0 || warn "invalid step: $num"
		done
	fi

	echo ""
	info "Steps marked to run:"
	for i in "${!steps[@]}"; do
		if [ "${run_step[i]}" -eq 1 ]; then
			printf "  ${GREEN}✔${NC}  %s\n" "${steps[i]}"
		fi
	done
	sep

	sep
	echo ""
	if ! prompt_yn "Run these steps now (no further prompts)?"; then
		info "exiting"
		exit 0
	fi
	AUTO_YES=1
}

# ── Run selected steps ─────────────────────────────────────────
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

# ── Summary ─────────────────────────────────────────────────────
print_summary() {
	step "Install Summary"

	if [ -z "${TARGET_ROOT_UUID:-}" ]; then
		TARGET_ROOT_UUID="$(blkid -s UUID -o value "$TARGET_ROOT" 2>/dev/null || echo "?")"
	fi

	cat <<SUMMARY

  ${BOLD}Installation complete!${NC}

  eMMC device:    $TARGET_EMMC
  Root UUID:      $TARGET_ROOT_UUID
  Kernel:         ${KERNEL_VERSION:-?}
  U-Boot:         ${UBOOT_BIN:-?}

  ${BOLD}To boot from eMMC:${NC}
  1. Power off the board
  2. Remove the microSD card
  3. Power on — it should boot from eMMC

  ${BOLD}If boot fails:${NC}
  - Connect serial (UART0: pins 8-10 on header)
  - Capture U-Boot output
  - Check that boot.scr is on the root partition (/boot/boot.scr)
  - Verify U-Boot was flashed to sector 16
  - log: $LOGFILE

SUMMARY
}

# ── Main ────────────────────────────────────────────────────────
main() {
	# Initialize log
	echo "=== Cubieboard4 eMMC Installer Wizard ===" > "$LOGFILE"
	log "Started at $(date -u)"

	main_menu

	# Run steps based on user selection
	while true; do
		select_steps

		root_check
		do_step 0 "Check prerequisites"       check_prereqs
		do_step 1 "Detect hardware"           detect_hardware
		do_step 2 "Detect boot assets"        detect_assets

		if [ "${run_step[1]:-0}" -eq 1 ] || [ "${run_step[2]:-0}" -eq 1 ]; then
			# Detection ran, save state
			:
		fi

		if [ "${run_step[3]:-0}" -eq 1 ] && [ -n "${TARGET_EMMC:-}" ]; then
			# Check if eMMC has partitions
			if [ ! -b "${TARGET_EMMC}p1" ] || [ ! -b "${TARGET_EMMC}p2" ]; then
				warn "eMMC partition layout missing/incomplete"
				if prompt_yn "Repartition eMMC?"; then
					repartition_emmc
				else
					info "repartition skipped (may cause issues later)"
				fi
			else
				do_step 3 "Repartition eMMC" repartition_emmc
			fi
		fi

		do_step 4 "Backup eMMC"              backup_emmc
		do_step 5 "Flash U-Boot"             flash_uboot
		do_step 6 "Format root partition"    format_rootfs

		# Only copy root if formated or if target seems empty
		COPY_NEEDED=0
		if [ "${run_step[7]:-0}" -eq 1 ]; then
			if [ -b "$TARGET_ROOT" ]; then
				TARGET_FSTYPE="$(blkid -s TYPE -o value "$TARGET_ROOT" 2>/dev/null || true)"
				if [ "$TARGET_FSTYPE" != "ext4" ]; then
					COPY_NEEDED=1
				else
					# Check if target has files
					ROOT_MOUNT="$(findmnt -n -o TARGET "$TARGET_ROOT" 2>/dev/null || true)"
					if [ -z "$ROOT_MOUNT" ]; then
						mkdir -p "$MOUNTPOINT"
						mount "$TARGET_ROOT" "$MOUNTPOINT" 2>/dev/null || true
						ROOT_MOUNT="$MOUNTPOINT"
					fi
					if [ -d "$ROOT_MOUNT" ]; then
						FILE_COUNT="$(ls -1 "$ROOT_MOUNT" 2>/dev/null | wc -l)"
						if [ "$FILE_COUNT" -le 2 ]; then
							COPY_NEEDED=1
						else
							info "target already has $FILE_COUNT entries"
							if prompt_yn "Target appears populated. Copy anyway (will overwrite)?"; then
								COPY_NEEDED=1
							fi
						fi
					fi
				fi
			fi
			if [ "$COPY_NEEDED" -eq 1 ]; then
				do_step 7 "Copy root filesystem"   copy_rootfs
			fi
		fi

		do_step 8 "Configure boot"           configure_boot
		do_step 9 "Verify installation"      verify_install

		print_summary
		log "=== Session completed ==="

		AUTO_YES=0
		if prompt_yn "Run again with different options?"; then
			continue
		else
			break
		fi
	done
}

main "$@"
