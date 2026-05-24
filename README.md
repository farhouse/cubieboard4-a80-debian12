# Cubieboard4 A80 Debian 12 revive

Repositorio de bring-up para **Cubieboard4 / CC-A80 (Allwinner A80)** con
Debian 12 armhf y kernel mainline. El resultado validado es una microSD que
bootea hasta shell con Ethernet, USB Type-A y WiFi AP6330 funcionando.

## Estado validado

Validado en hardware real el 2026-05-22:

| Subsistema | Estado | Notas |
|---|---|---|
| Boot desde microSD | Funciona | U-Boot carga `boot.scr`; Linux usa `mmcblk0p2` |
| Debian 12 armhf | Funciona | Kernel `6.1.0-37-armmp` |
| Ethernet | Funciona | RTL8211E, link Gigabit Full Duplex |
| USB Type-A | Funciona | Hub interno `05e3:0608`; pendrive probado en los 4 puertos |
| WiFi AP6330 | Funciona | `wlan0` levanta y escanea redes; BCM4330/4 |
| eMMC | Detectada | Linux la ve como eMMC de 7.30 GiB; boot desde eMMC pendiente |
| Bluetooth | Pendiente | Falta configurar firmware/UART |
| VGA/HDMI | Pendiente | No validado todavia |
| GPU PowerVR G6230 | Sin aceleracion mainline | Falta firmware publico para BVNC `1.75.2.30` |

La evidencia detallada esta en
[docs/estado-validado.md](docs/estado-validado.md) y
[logs/2026-05-22-final-wifi-validation.log](logs/2026-05-22-final-wifi-validation.log).

## Que hay en este repo

- [dtb/sun9i-a80-cubieboard4.dtb](dtb/sun9i-a80-cubieboard4.dtb): DTB validado
  para boot SD, USB Type-A, eMMC detectada y WiFi SDIO AP6330.
- [docs/](docs/): estado consolidado, matriz de pruebas, referencias tecnicas.
- [notes/](notes/): bitacora de investigacion y handoffs.
- [logs/](logs/): evidencia de validacion.

No se versionan imagenes completas, dumps ni firmwares vendor por tamano y
licenciamiento. Para reproducir la microSD se necesitan artefactos externos.
El inventario de imagenes, mirrors y SHA256 esta en
[docs/artefactos-externos.md](docs/artefactos-externos.md).

## Base recomendada por Johan

Johan mantiene builds vanilla Debian/Ubuntu para Cubieboard4:

```text
https://sd-card-images.johang.se/boards/cubieboard4.html
```

Links directos recomendados al 2026-05-24:

```sh
curl -O https://dl.sd-card-images.johang.se/boots/2026-05-01/boot-cubieboard4.bin.gz
curl -O https://dl.sd-card-images.johang.se/debians/2026-05-18/debian-bookworm-armhf-ja3iex.bin.gz
```

El servidor de Johan rota builds viejas; si esos links vencen, usar la pagina
de Cubieboard4 para elegir el boot image y Debian Bookworm mas recientes.

La imagen Debian usa como password de `root` el sufijo del nombre de archivo.
Para `debian-bookworm-armhf-ja3iex.bin.gz`, el password es:

```text
ja3iex
```

## Artefactos necesarios

Para reproducir la imagen con los fixes de este repo se necesitan:

| Archivo | Origen | Uso |
|---|---|---|
| `boot-cubieboard4.bin.gz` | Johan | Boot/U-Boot base para Cubieboard4 |
| `debian-bookworm-armhf-ja3iex.bin.gz` | Johan | Rootfs Debian 12 armhf |
| `dtb/sun9i-a80-cubieboard4.dtb` | Este repo | DTB final validado |
| `fw_bcm40183b2_ag.bin` | Imagen vendor/Linaro | Firmware WiFi AP6330 |
| `nvram_ap6330.txt` | Imagen vendor/Linaro | NVRAM WiFi AP6330 |

Los nombres usados durante la validacion original fueron:

- `images/boot-cubieboard4.bin.gz`
- `images/debian-bookworm-armhf-vim3ve.bin.gz`
- `android4.4-cb4-emmc-v4.3.20170717.img.7z` o una imagen vendor/Linaro con
  `lib/firmware/ap6330/`

La validacion documentada en `logs/` se hizo con una build anterior de Johan
(`vim3ve`). El flujo es el mismo para la build `ja3iex`; si se usa una build
nueva, registrar fecha y hashes.

El link MEGA y los hashes de las imagenes locales estan documentados. Pendiente:
subir los artefactos a una GitHub Release si se decide preservarlos tambien
alli. Ver
[docs/artefactos-externos.md](docs/artefactos-externos.md),
[notes/2026-05-21-inspeccion-imagenes-vendor.md](notes/2026-05-21-inspeccion-imagenes-vendor.md)
y [docs/referencias-a80.md](docs/referencias-a80.md).

## Crear la imagen microSD

Ejemplo en macOS/Linux:

```sh
mkdir -p /private/tmp/cb4-bookworm
cd /private/tmp/cb4-bookworm

curl -O https://dl.sd-card-images.johang.se/boots/2026-05-01/boot-cubieboard4.bin.gz
curl -O https://dl.sd-card-images.johang.se/debians/2026-05-18/debian-bookworm-armhf-ja3iex.bin.gz

shasum -a 256 boot-cubieboard4.bin.gz debian-bookworm-armhf-ja3iex.bin.gz

zcat boot-cubieboard4.bin.gz debian-bookworm-armhf-ja3iex.bin.gz \
  > cubieboard4-bookworm-test.img
```

La imagen resultante debe tener:

- particion 1: FAT32 boot, sector `8192`, 28 MiB;
- particion 2: ext4 rootfs, sector `65536`, aproximadamente 3.5 GiB.

## Instalar el DTB validado

Montar la particion rootfs ext4 de la imagen desde Linux o una VM Linux. macOS
no monta ext4 de forma nativa.

La particion rootfs empieza en el sector `65536`; con sectores de 512 bytes,
el offset es `33554432`.

```sh
sudo mkdir -p /mnt/cb4-root
sudo mount -o loop,offset=33554432 \
  /private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img \
  /mnt/cb4-root

sudo cp /ruta/al/repo/dtb/sun9i-a80-cubieboard4.dtb \
  /mnt/cb4-root/boot/sun9i-a80-cubieboard4.dtb

sync
sudo umount /mnt/cb4-root
```

En las pruebas, U-Boot cargo el DTB desde la particion ext4:

```text
/boot/sun9i-a80-cubieboard4.dtb
```

El cambio critico para boot estable es `broken-cd` en `mmc0`; sin eso, U-Boot
SPL puede arrancar, pero U-Boot/Linux pueden perder la SD por card-detect.

## Instalar firmware WiFi AP6330

Con el mismo rootfs montado en `/mnt/cb4-root`, copiar los firmwares Broadcom
con los nombres que espera `brcmfmac`:

```sh
sudo mkdir -p /mnt/cb4-root/lib/firmware/brcm
sudo cp fw_bcm40183b2_ag.bin \
  /mnt/cb4-root/lib/firmware/brcm/brcmfmac4330-sdio.bin
sudo cp nvram_ap6330.txt \
  /mnt/cb4-root/lib/firmware/brcm/brcmfmac4330-sdio.txt
sync
```

En el boot validado, el kernel mostro:

```text
brcmfmac: brcm_fw_alloc_request: using brcm/brcmfmac4330-sdio for chip BCM4330/4
brcmfmac: Firmware: BCM4330/4 wl0: Jan  6 2014 15:11:29 version 5.90.195.89
wlan0: ether e0:76:d0:b0:d1:ea
```

## Grabar la microSD

En macOS, identificar primero el disco correcto:

```sh
diskutil list external physical
```

Luego reemplazar `/dev/disk4` por el dispositivo real:

```sh
diskutil unmountDisk force /dev/disk4
sudo dd if=/private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img \
  of=/dev/rdisk4 bs=4m conv=sync status=progress
sync
diskutil eject /dev/disk4
```

Atencion: `dd` destruye el contenido del disco destino.

## Consola serial

Parametros validados:

- 115200 baudios
- 8N1
- sin flow control

Ejemplo:

```sh
picocom -b 115200 --databits 8 --parity n --stopbits 1 --flow n /dev/cu.usbserial-14230
```

En tu maquina puede cambiar el dispositivo serial. Revisar con:

```sh
ls /dev/cu.usbserial*
```

## Validar el sistema

Despues de bootear, estos comandos reproducen la validacion minima.

Boot y almacenamiento:

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

Resultados esperados:

- SD como `mmcblk0`.
- eMMC como `mmcblk1`.
- Hub USB Genesys Logic `05e3:0608`.
- `wlan0` presente y capaz de escanear redes.
- Ethernet con link Gigabit si hay cable conectado.

## Cambios tecnicos clave

El DTB validado corrige estos puntos:

- `mmc0`: SD con `broken-cd`.
- `mmc1`: AP6330 por SDIO 4-bit, no eMMC.
- `mmc2`: eMMC 8-bit.
- `usbphy1` y `usbphy3`: `phy-supply` asociado a reguladores VBUS.
- `wifi_pwrseq`: reset/power sequencing para AP6330.
- firmware AP6330 instalado como `brcmfmac4330-sdio.*`.

Ver el detalle DTS en [docs/estado-validado.md](docs/estado-validado.md).

## Pendientes

- Publicar enlaces y hashes exactos de los artefactos externos.
- Agregar o reconstruir el DTS fuente correspondiente al DTB final.
- Validar boot desde eMMC.
- Validar VGA/HDMI.
- Configurar Bluetooth AP6330.
- Capturar un boot log limpio completo con el DTB final.
