# Cubieboard4 A80 Debian 12 revive

Bring-up and recovery repository for **Cubieboard4 / CC-A80 (Allwinner A80)**
running Debian 12 armhf with a mainline kernel. The validated result is a
microSD or eMMC image that boots to shell with Ethernet, USB Type-A, AP6330 WiFi,
and eMMC boot working.

Some investigation notes and raw logs are still in Spanish. The stable
reproduction path is documented here in English.

## Validated Status

Validated on real hardware on 2026-05-26:

| Subsystem | Status | Notes |
|---|---|---|
| microSD boot | Working | U-Boot loads `boot.scr`; uses `root=UUID=...` |
| eMMC boot (no SD) | Working | Fixed: `get_mclk_offset()` typo `CONFIG_MACH_SUN9I_A80` → `CONFIG_MACH_SUN9I` |
| Debian 12 armhf | Working | Kernel `6.1.0-48-armmp` |
| Ethernet | Working | RTL8211E, Gigabit Full Duplex link |
| USB Type-A | Working | Internal `05e3:0608` hub; flash drive tested on all 4 ports |
| AP6330 WiFi | Working | `wlan0` comes up and scans networks; BCM4330/4 |
| Bluetooth | Pending | Firmware/UART setup still needed |
| VGA/HDMI | Pending | Not validated yet |
| PowerVR G6230 GPU | No mainline acceleration | Public firmware for BVNC `1.75.2.30` is missing |

Detailed evidence is available in
[docs/estado-validado.md](docs/estado-validado.md) and
[notes/2026-05-26-emmc-boot-fix-clock-register.md](notes/2026-05-26-emmc-boot-fix-clock-register.md).

## Repository Contents

- [dtb/sun9i-a80-cubieboard4.dtb](dtb/sun9i-a80-cubieboard4.dtb): validated
  DTB for SD boot, USB Type-A, eMMC detection, and AP6330 SDIO WiFi.
- [scripts/build-sd-image.sh](scripts/build-sd-image.sh): reproducible SD
  image builder for Linux hosts.
- [scripts/install-to-emmc.sh](scripts/install-to-emmc.sh): conservative
  SD-to-eMMC rootfs installer for testing.
- [docs/](docs/): consolidated status, test matrix, and technical references.
- [notes/](notes/): investigation notes and handoffs.
- [logs/](logs/): validation evidence.

Full OS images, dumps, and vendor firmware are not committed to git because of
size and licensing. Reproducing the microSD image requires external artifacts.
The image inventory, mirrors, and SHA256 checksums are documented in
[docs/artefactos-externos.md](docs/artefactos-externos.md).

## Johan Base Images

Many thanks to **Johan Ahlberg** ([johang](https://github.com/johang)) — his
SD-card images are the foundation this work is built on. Without his tooling
and pre-built Debian/Ubuntu images for the Cubieboard4, this project would not
exist.

Johan maintains vanilla Debian/Ubuntu SD-card images for Cubieboard4:

```text
https://sd-card-images.johang.se/boards/cubieboard4.html
```

Direct links recommended by Johan as of 2026-05-24:

```sh
curl -O https://dl.sd-card-images.johang.se/boots/2026-05-01/boot-cubieboard4.bin.gz
curl -O https://dl.sd-card-images.johang.se/debians/2026-05-18/debian-bookworm-armhf-ja3iex.bin.gz
```

Johan's server rotates old builds. If those links expire, use the Cubieboard4
page to pick the latest boot image and Debian Bookworm rootfs.

The Debian image uses the filename suffix as the `root` password. For
`debian-bookworm-armhf-ja3iex.bin.gz`, the password is:

```text
ja3iex
```

## Required Artifacts

To reproduce the validated image with this repository's fixes, use the
preserved assets from the GitHub Release `external-images-2026-05`:

| File | Source | Purpose |
|---|---|---|
| `boot-cubieboard4.bin.gz` | Johan, mirrored in this repo release | Base boot/U-Boot image for Cubieboard4 |
| `debian-bookworm-armhf-vim3ve.bin.gz` | Johan, mirrored in this repo release | Debian 12 armhf rootfs used during validation |
| `dtb/sun9i-a80-cubieboard4.dtb` | This repository | Final validated DTB |
| `u-boot-sunxi-with-spl-fixed.bin` | This repository | Fixed U-Boot (eMMC clock register, installed to /boot/) |
| `fw_bcm40183b2_ag.bin` | Vendor/Linaro image | AP6330 WiFi firmware |
| `nvram_ap6330.txt` | Vendor/Linaro image | AP6330 WiFi NVRAM |

Original validation used these local filenames:

- `images/boot-cubieboard4.bin.gz`
- `images/debian-bookworm-armhf-vim3ve.bin.gz`
- `android4.4-cb4-emmc-v4.3.20170717.img.7z` or another vendor/Linaro image
  containing `lib/firmware/ap6330/`

The same flow should work with newer Johan builds, such as `ja3iex`, but a new
boot should be recorded with dates and hashes.

The MEGA mirror, GitHub Release, and local image checksums are documented in
[docs/artefactos-externos.md](docs/artefactos-externos.md),
[notes/2026-05-21-inspeccion-imagenes-vendor.md](notes/2026-05-21-inspeccion-imagenes-vendor.md),
and [docs/referencias-a80.md](docs/referencias-a80.md).

## Build The microSD Image

For now, the automatic builder **only works on Linux**. It needs `losetup` and
root-mounted ext4 support in order to patch the rootfs partition inside the
image. On macOS you can manually download and concatenate the image pieces, but
installing the DTB and firmware requires Linux or a Linux VM.

Recommended flow from a Linux host or Linux VM:

```sh
sudo scripts/build-sd-image.sh \
  --work-dir /tmp/cb4-bookworm \
  --output /tmp/cb4-bookworm/cubieboard4-a80-debian12-sd.img
```

The script downloads the preserved assets from the GitHub Release
`external-images-2026-05`, verifies SHA256 checksums, builds the SD image,
installs the validated DTB, the fixed U-Boot binary (`u-boot-sunxi-with-spl-fixed.bin`)
to `/boot/u-boot-sunxi-with-spl.bin`, and copies the AP6330 firmware using the
filenames expected by `brcmfmac`. It also regenerates `/boot/boot.scr` so the
kernel uses `root=UUID=...` instead of a fragile `/dev/mmcblkNp2` device name.

The fixed U-Boot is required for eMMC boot without SD. When running the
install-to-emmc.sh script on the CB4, it will flash this binary from
`/boot/u-boot-sunxi-with-spl.bin` to the eMMC at sector 16.

Host requirements:

- Linux with root permissions for `losetup` and ext4 mounting;
- `curl` or `wget`;
- `sha256sum`, `gzip`, `blkid`, `losetup`, `mount`, `umount`;
- `mkimage` from `u-boot-tools`;
- `7z`, unless using `--firmware-dir` or `--no-firmware`.

Example using already extracted firmware:

```sh
sudo scripts/build-sd-image.sh \
  --firmware-dir /path/to/lib/firmware/ap6330 \
  --output /tmp/cubieboard4-a80-debian12-sd.img
```

Partial manual flow for macOS/Linux:

```sh
mkdir -p /private/tmp/cb4-bookworm
cd /private/tmp/cb4-bookworm

curl -L -O https://github.com/farhouse/cubieboard4-a80-debian12/releases/download/external-images-2026-05/boot-cubieboard4.bin.gz
curl -L -O https://github.com/farhouse/cubieboard4-a80-debian12/releases/download/external-images-2026-05/debian-bookworm-armhf-vim3ve.bin.gz

shasum -a 256 boot-cubieboard4.bin.gz debian-bookworm-armhf-vim3ve.bin.gz

zcat boot-cubieboard4.bin.gz debian-bookworm-armhf-vim3ve.bin.gz \
  > cubieboard4-bookworm-test.img
```

The resulting image should contain:

- partition 1: FAT32 boot, sector `8192`, 28 MiB;
- partition 2: ext4 rootfs, sector `65536`, around 3.5 GiB.

## Install The Validated DTB

Mount the image's ext4 rootfs partition from Linux or a Linux VM. macOS does
not mount ext4 natively.

The rootfs partition starts at sector `65536`; with 512-byte sectors, the
offset is `33554432`.

```sh
sudo mkdir -p /mnt/cb4-root
sudo mount -o loop,offset=33554432 \
  /private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img \
  /mnt/cb4-root

sudo cp /path/to/repo/dtb/sun9i-a80-cubieboard4.dtb \
  /mnt/cb4-root/boot/sun9i-a80-cubieboard4.dtb

sync
sudo umount /mnt/cb4-root
```

During validation, U-Boot loaded the DTB from the ext4 partition:

```text
/boot/sun9i-a80-cubieboard4.dtb
```

The critical fixes for stable boot are:
- `broken-cd` on `mmc0` — without it, U-Boot/Linux can lose the SD card.
- `CONFIG_MACH_SUN9I` in `get_mclk_offset()` — without it, eMMC boot fails
  because U-Boot proper writes MMC2 clock register to the wrong address.

## Install AP6330 WiFi Firmware

With the same rootfs mounted at `/mnt/cb4-root`, copy the Broadcom firmware
using the names expected by `brcmfmac`:

```sh
sudo mkdir -p /mnt/cb4-root/lib/firmware/brcm
sudo cp fw_bcm40183b2_ag.bin \
  /mnt/cb4-root/lib/firmware/brcm/brcmfmac4330-sdio.bin
sudo cp nvram_ap6330.txt \
  /mnt/cb4-root/lib/firmware/brcm/brcmfmac4330-sdio.txt
sync
```

In the validated boot, the kernel showed:

```text
brcmfmac: brcm_fw_alloc_request: using brcm/brcmfmac4330-sdio for chip BCM4330/4
brcmfmac: Firmware: BCM4330/4 wl0: Jan  6 2014 15:11:29 version 5.90.195.89
wlan0: ether e0:76:d0:b0:d1:ea
```

## Write The microSD Card

On macOS, identify the correct target disk first:

```sh
diskutil list external physical
```

Then replace `/dev/disk4` with the real target device:

```sh
diskutil unmountDisk force /dev/disk4
sudo dd if=/private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img \
  of=/dev/rdisk4 bs=4m conv=sync status=progress
sync
diskutil eject /dev/disk4
```

Warning: `dd` destroys the contents of the target disk.

## Serial Console

Validated settings:

- 115200 baud
- 8N1
- no flow control

Example:

```sh
picocom -b 115200 --databits 8 --parity n --stopbits 1 --flow n /dev/cu.usbserial-14230
```

The serial device name can differ on your machine. Check it with:

```sh
ls /dev/cu.usbserial*
```

## Validate The System

After booting, these commands reproduce the minimum validation.

Boot and storage:

```sh
uname -a
cat /proc/partitions
findmnt /
```

USB:

```sh
lsusb
cat /sys/kernel/debug/usb/devices
```

WiFi:

```sh
ifconfig wlan0 up
iw dev wlan0 scan
```

Ethernet:

```sh
dmesg | grep -i 'Link is Up'
```

Expected results:

- SD and eMMC both appear as `mmcblk*` block devices.
- Depending on probe order, SD may appear as `mmcblk0` or `mmcblk1`; eMMC may
  appear as `mmcblk1` or `mmcblk2`.
- SD and eMMC device numbers may change across boots if SDIO WiFi probes as an
  MMC device first. Boot scripts should use filesystem `UUID`, not
  `/dev/mmcblkNp2`.
- SD and eMMC may share `PARTUUID` if they come from the same layout; avoid
  `root=PARTUUID=...` while both media are present unless identifiers are
  regenerated.
- Genesys Logic USB hub `05e3:0608`.
- `wlan0` present and able to scan networks.
- Ethernet reports a Gigabit link if a cable is connected.

## Key Technical Changes

### Device Tree fixes

The validated DTB (`dtb/sun9i-a80-cubieboard4.dtb`) includes:

- `mmc0`: SD with `broken-cd`.
- `mmc1`: AP6330 over 4-bit SDIO, not eMMC.
- `mmc2`: 8-bit eMMC with `mmc-hs200-1.8v`.
- `usbphy1` and `usbphy3`: `phy-supply` connected to VBUS regulators.
- `wifi_pwrseq`: AP6330 reset/power sequencing.
- AP6330 firmware installed as `brcmfmac4330-sdio.*`.

See DTS details in [docs/estado-validado.md](docs/estado-validado.md).

### U-Boot fix: eMMC clock register

**Root cause**: `get_mclk_offset()` in `drivers/mmc/sunxi_mmc.c` checked
`CONFIG_MACH_SUN9I_A80` (does not exist) instead of `CONFIG_MACH_SUN9I`.
U-Boot proper wrote MMC2 clock config to address `0x06000090` instead of
`0x06000418`, corrupting CMD2 (ALL_CID) and preventing eMMC detection.

**Fix**: `IS_ENABLED(CONFIG_MACH_SUN9I)` at line 649.

**Result**: SPL (non-DM path) worked because it used `CCU_MMC2_CLK_CFG`
directly; U-Boot proper (DM path) now gets the correct clock register offset
and successfully initializes MMC2.

See [notes/2026-05-26-emmc-boot-fix-clock-register.md](notes/2026-05-26-emmc-boot-fix-clock-register.md)
for the full analysis.

## Pending Work

- Add or reconstruct the DTS source corresponding to the final DTB.
- Validate VGA/HDMI.
- Configure AP6330 Bluetooth.
- Send U-Boot upstream patch: typo `CONFIG_MACH_SUN9I_A80` affects all sun9i-A80 boards.

## eMMC Install Script

There is a conservative installer for copying the currently running SD system
to eMMC and flashing the fixed U-Boot:

```sh
sudo scripts/install-to-emmc.sh --backup-dir /media/usb
```

It runs in dry-run mode by default. To execute for real:

```sh
sudo scripts/install-to-emmc.sh --backup-dir /media/usb --execute
```

The script auto-detects the source SD and target eMMC devices (no more
hardcoded `/dev/mmcblk1`). It:

1. Backs up the first 32 MiB of eMMC to the USB drive.
2. Flashes `/boot/u-boot-sunxi-with-spl.bin` (the fixed binary, included in
   the SD image by the builder) to the eMMC user area at **sector 16** (where
   the A80 boot ROM reads it).
3. Formats and copies the rootfs via `rsync` or `tar`.
4. Generates a `boot.scr` with `root=UUID=...` using U-Boot's distro-boot
   variables.

The eMMC boot blocker (`MMC: no card present`) was resolved on 2026-05-26.
See [notes/2026-05-26-emmc-boot-fix-clock-register.md](notes/2026-05-26-emmc-boot-fix-clock-register.md).
