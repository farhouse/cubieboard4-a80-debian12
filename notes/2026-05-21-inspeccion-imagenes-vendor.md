# Inspeccion de imagenes vendor Cubieboard4

Fecha: 2026-05-21

## Material inspeccionado

- `images/cb4-debian-server-hdmi-card-v1.0.img.7z`
- `images/cb4-debian-server-hdmi-emmc-v1.0.img.7z`
- `images/boot-cubieboard4.bin.gz`
- `images/linaro-desktop-cb4-emmc-hdmi-v1.1.img.7z`
- `u-boot/`

Las imagenes se extrajeron temporalmente en `/private/tmp/cb4-images` y los archivos seleccionados en `/private/tmp/cb4-analysis`.

## Estructura de imagenes

Imagen SD:

- MBR con dos particiones Linux.
- Particion 1: FAT16, 12 MiB, contiene `uImage`.
- Particion 2: ext4, 837 MiB, raiz Debian-like.
- Kernel: `Linux-3.4.39`, uImage legacy, creado el 2015-04-21.

Imagen eMMC:

- MBR con dos particiones Linux.
- Particion 1: FAT16, 12 MiB.
- Particion 2: ext4, 346 MiB.
- Contiene `rootfs.tar.gz`, `uImage`, `u-boot-spl.bin` y `u-boot.bin`.

Imagen Linaro desktop:

- `linaro-desktop-cb4-emmc-hdmi-v1.1.img.7z`, fecha interna 2015-09-01.
- MBR con dos particiones Linux.
- Particion 1: FAT16, 12 MiB, contiene `uImage`.
- Particion 2: ext4, 760 MiB.
- Contiene `rootfs.tar.gz`, `uImage`, `u-boot-spl.bin` y `u-boot.bin`.
- Kernel: `Linux-3.4.39`, uImage legacy, creado el 2015-09-01.

## Bootloader vendor

La imagen vendor contiene U-Boot viejo:

- `U-Boot 2011.09-rc1 (Oct 08 2014 - 10:38:33) Allwinner Technology`
- Usa `sys_config.fex`/`script.bin`, no un flujo DTB moderno puro.
- Archivos relevantes en `root/boot-file/`:
  - `sys_config.fex`
  - `hdmi_sys_config.fex`
  - `vga_sys_config.fex`
  - `u-boot-spl.bin`
  - `u-boot-sun9iw1p1.bin`
  - `u-boot-sun9iw1p1_card2.bin`
  - `update_sys_config.sh`

## Wi-Fi

La imagen SD trae firmware y modulos para AP6330/Broadcom:

- Firmware: `lib/firmware/ap6330/`
  - `fw_bcm40183b2_ag.bin`
  - `fw_bcm40183b2_ag_apsta.bin`
  - `fw_bcm40183b2_ag_p2p.bin`
  - `nvram_ap6330.txt`
  - `bcm40183b2.hcd`
- Modulos kernel 3.4.39:
  - `bcmdhd.ko`
  - `brcmfmac.ko`
  - `brcmutil.ko`
  - tambien existen `8723bs.ko` y `8188eu.ko`

`sys_config.fex` define:

- `wifi_used = 1`
- `wifi_sdc_id = 1`
- `wifi_mod_sel = 5` (AP6330)
- `wifi_power = "axp22_dldo1"`
- `wifi_power_ext1 = "axp15_cldo3"`
- `wifi_power_ext2 = "axp22_ldoio0"`
- `ap6xxx_wl_regon = port:PL02`
- `ap6xxx_wl_host_wake = port:PL03`
- `ap6xxx_bt_regon = port:PL05`
- `ap6xxx_bt_wake = port:PL08`
- `ap6xxx_bt_host_wake = port:PL04`
- `ap6xxx_lpo_use_apclk = 2`

La imagen Linaro confirma el mismo patron:

- Trae `lib/firmware/ap6330/` con `fw_bcm40183b2_*`, `nvram_ap6330.txt` y `bcm40183b2.hcd`.
- Trae los mismos modulos principales: `bcmdhd.ko`, `brcmfmac.ko`, `brcmutil.ko`, `8723bs.ko` y `8188eu.ko`.
- Su `root/boot-file/sys_config.fex` mantiene `wifi_mod_sel = 5`, `wifi_sdc_id = 1` y AP6330 sobre SDIO.
- El diff contra el `sys_config.fex` de la imagen Debian vendor solo muestra cambios menores de formato; no cambia `wifi_para`, `mmc1_para` ni `mmc2_para`.

## MMC/eMMC comparacion clave

En `sys_config.fex`:

- `mmc0`: SD, 4-bit, `PF0-PF5`, detect en `PH18`.
- `mmc1`: SDIO Wi-Fi, 4-bit, `PG0-PG5`, `sdc_isio = 1`.
- `mmc2`: eMMC, 8-bit, `PC6-PC16`, incluye `emmc_rst = PC16`.

Riesgo detectado: el DTS actual de `u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts` configura `mmc1` con propiedades de eMMC (`bus-width = <8>`, `non-removable`, `cap-mmc-hw-reset`, `mmc-hs200-1.8v`, `no-sd`) aunque el FEX vendor lo usa como SDIO Wi-Fi de 4 bits. Esto probablemente bloquea el Wi-Fi.

La imagen Linaro refuerza esta hipotesis: tambien resuelve Wi-Fi usando AP6330 en `mmc1` SDIO de 4 bits, mientras deja eMMC en `mmc2`.

## USB

El FEX vendor define USB por `usb*_para` y usa control de VBUS por GPIO/PMIC:

- `usb0`: OTG, `usb_port_type = 2`, ID en `PH16`, VBUS detect por `axp_ctrl`, drive VBUS por `power4`.
- `usb1`: host, `usb_port_type = 1`, drive VBUS por `PH14`.

Hay que mapear estos datos contra los nodos `usbphy*`, `ehci*` y reguladores del DTS moderno.

## Proximo trabajo recomendado

1. Guardar los `.fex` vendor como referencia durable en `docs/device-tree/`.
2. Corregir `mmc1` en DTS para SDIO/AP6330 y dejar `mmc2` como eMMC.
3. Traducir `wifi_para` a nodos DTS: power sequence, GPIO reset/wake, clock LPO y supplies.
4. Comparar `usb*_para` contra reguladores `vcc33-usbh`, `vdd-cpus-09-usbh` y GPIOs VBUS.
5. Preparar una tabla FEX -> DTS para cada subsistema.
