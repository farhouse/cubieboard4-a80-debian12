# Handoff: Bookworm SD y U-Boot 2025

Fecha: 2026-05-21

## Objetivo

Preparar una SD de prueba para Cubieboard4 A80 usando:

- `images/boot-cubieboard4.bin.gz`
- `images/debian-bookworm-armhf-vim3ve.bin.gz`

La meta inicial no es Wi-Fi funcionando, sino lograr que U-Boot lea la SD, cargue el rootfs Bookworm y capture logs para ajustar DTS/firmware.

## Imagen base creada

Archivos descomprimidos en `/private/tmp/cb4-bookworm/`:

- `boot-cubieboard4.bin` (32 MiB)
- `debian-bookworm-armhf-vim3ve.bin` (~3.5 GiB)

Imagen combinada:

```sh
cp /private/tmp/cb4-bookworm/boot-cubieboard4.bin \
  /private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img

dd if=/private/tmp/cb4-bookworm/debian-bookworm-armhf-vim3ve.bin \
  of=/private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img \
  bs=1m seek=32 conv=notrunc status=progress
```

Particiones verificadas:

- Particion 1: FAT32 boot, sector `8192`, 28 MiB.
- Particion 2: ext4 rootfs, sector `65536`, ~3.5 GiB.

## Serial

Adaptador detectado:

- `/dev/cu.usbserial-14230`
- Prolific USB-serial.
- Config: `115200 8N1`, sin flow control.

Comando que funciono:

```sh
picocom -b 115200 --databits 8 --parity n --stopbits 1 --flow n /dev/cu.usbserial-14230
```

Salir de `picocom`: `Ctrl-A`, `Ctrl-X`.

## Estado de U-Boot

Arranque observado:

```text
U-Boot SPL 2025.04johang-dirty (Jun 01 2025 - 02:32:17 +0000)
DRAM: 2048 MiB
Trying to boot from MMC1

U-Boot 2025.04johang-dirty (Jun 01 2025 - 02:32:17 +0000) Allwinner Technology
CPU:   Allwinner A80 (SUN9I)
Model: Cubietech Cubieboard4
DRAM:  2 GiB
MMC:   mmc@1c0f000: 0, mmc@1c10000: 2, mmc@1c11000: 1
Loading Environment from FAT... MMC: no card present
** Bad device specification mmc 0 **
```

`version` responde correctamente en prompt `=>`.

## Hallazgo principal: card-detect de SD

U-Boot proper no lee la SD desde `mmc 0`:

```text
mmc dev 0
MMC: no card present
```

Pero SPL si arranca desde la SD, asi que el problema esta en U-Boot proper/DTB, no en la tarjeta ni en el offset de la imagen.

FDT activo original:

```text
mmc@1c0f000 {
    ...
    bus-width = <0x04>;
    cd-gpios = <0x1a 0x07 0x12 0x01>;  /* PH18, active low */
};
```

GPIO observado:

```text
gpio input PH18
gpio: pin PH18 (gpio 242) value is 1
```

Con parche `active high`, el DTB activo cambio a:

```text
cd-gpios = <0x1a 0x07 0x12 0x00>;
```

Pero luego `PH18` leyo `0`, y U-Boot siguio reportando `MMC: no card present`. Conclusion: no conviene depender de `PH18` para esta prueba.

## Imagenes generadas

Base:

- `/private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img`

Parche 1, card-detect active high:

- `/private/tmp/cb4-bookworm/cubieboard4-bookworm-test-cdactivehigh.img`
- Cambia un byte del DTB embebido:
  - `cd-gpios = <0x1a 0x07 0x12 0x00>`
- No resolvio `mmc 0`.

Parche 2, ignorar card-detect:

- `/private/tmp/cb4-bookworm/cubieboard4-bookworm-test-nocd.img`
- Cambia un byte del DTB embebido, renombrando la propiedad:
  - `cd-gpios` -> `xd-gpios`
- Verificado con `dtc`:

```text
mmc@1c0f000 {
    ...
    bus-width = <0x04>;
    xd-gpios = <0x1a 0x07 0x12 0x01>;
};
```

Esta es la proxima imagen a probar.

## Comando para grabar SD

Dispositivo usado durante la sesion:

- `/dev/disk4`
- raw: `/dev/rdisk4`

Verificar siempre antes con `diskutil list external physical`.

```sh
diskutil unmountDisk force /dev/disk4

sudo dd if=/private/tmp/cb4-bookworm/cubieboard4-bookworm-test-nocd.img \
  of=/dev/rdisk4 bs=4m conv=sync status=progress

sync
diskutil eject /dev/disk4
```

## Proxima prueba en U-Boot

Con la imagen `nocd`, frenar en prompt y correr:

```text
version
mmc list
mmc dev 0
mmc info
part list mmc 0
fstype mmc 0:1
fstype mmc 0:2
ls mmc 0:1
ls mmc 0:2 /boot
boot
```

Si `mmc 0` funciona, dejar que `boot` intente cargar Bookworm y capturar todo el log.

## Wi-Fi/DTS pendiente

De la inspeccion de imagenes vendor y Linaro:

- Wi-Fi funcional usa AP6330/Broadcom.
- `wifi_mod_sel = 5`
- Wi-Fi esta en `mmc1`, SDIO 4-bit, pines `PG0-PG5`.
- eMMC esta en `mmc2`, 8-bit, pines `PC6-PC16`.
- Firmware vendor relevante:
  - `lib/firmware/ap6330/fw_bcm40183b2_ag.bin`
  - `lib/firmware/ap6330/fw_bcm40183b2_ag_p2p.bin`
  - `lib/firmware/ap6330/fw_bcm40183b2_ag_apsta.bin`
  - `lib/firmware/ap6330/nvram_ap6330.txt`
  - `lib/firmware/ap6330/bcm40183b2.hcd`

El FDT activo de U-Boot ya muestra `mmc1` como SDIO de 4 bits con `wifi-pwrseq`, y `mmc2` como eMMC 8-bit. El bloqueo actual no es Wi-Fi, sino que U-Boot proper no detecta la SD en `mmc0` por card-detect.
