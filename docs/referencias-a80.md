# Referencias tecnicas A80

Fecha de consolidacion: 2026-05-24

Este repo no versiona manuales completos, imagenes vendor ni arboles fuente
grandes. Esta pagina lista las referencias externas usadas para que otra
persona pueda repetir la investigacion.

## Documentacion Allwinner A80

- A80 Datasheet v1.3, 2015-05-10:
  `https://github.com/allwinner-zh/documents/raw/master/A80/A80_Datasheet_v1.3_20150510.pdf`
- A80 User Manual v1.3.1, 2015-05-13:
  `https://github.com/allwinner-zh/documents/tree/master/A80`
- A80 Datasheet v1.0, espejo linux-sunxi:
  `http://dl.linux-sunxi.org/A80/A80_Datasheet_Revision_1.0_0404.pdf`

## Fuentes vendor y upstream

- Johan Ahlberg SD card images para Cubieboard4:
  `https://sd-card-images.johang.se/boards/cubieboard4.html`
- Boot image Cubieboard4 usado como base actual:
  `https://dl.sd-card-images.johang.se/boots/2026-05-01/boot-cubieboard4.bin.gz`
- Debian Bookworm armhf usado como base actual:
  `https://dl.sd-card-images.johang.se/debians/2026-05-18/debian-bookworm-armhf-ja3iex.bin.gz`
- Kernel vendor Cubieboard CC-A80:
  `https://github.com/cubieboard/CC-A80-kernel-source`
- SDK A80 browseable:
  `https://dl.linux-sunxi.org/SDK/A80/`
- U-Boot mainline:
  `https://source.denx.de/u-boot/u-boot`
- Linux mainline:
  `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git`
- linux-firmware:
  `https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git`
- Mesa:
  `https://gitlab.freedesktop.org/mesa/mesa`

## Imagenes mencionadas en notas

Las imagenes se mantienen fuera de git por tamano y por licenciamiento. Los
nombres se conservan en notas/logs para trazabilidad:

- `android4.4-cb4-emmc-v4.3.20170717.img.7z`
- `linaro-desktop-cb4-emmc-hdmi-v1.1.img.7z`
- `cb4-debian-server-hdmi-card-v1.0.img.7z`
- `cb4-debian-server-hdmi-emmc-v1.0.img.7z`
- `debian-bookworm-armhf-vim3ve.bin.gz`
- `boot-cubieboard4.bin.gz`

Si alguna prueba depende de una imagen especifica, registrar en `notes/` o
`logs/` el origen exacto, hash y fecha de descarga.
