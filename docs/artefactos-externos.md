# Artefactos externos

Fecha de consolidacion: 2026-05-27

Este proyecto evita versionar imagenes completas dentro del historial git. Las
imagenes se conservan como artefactos externos y se referencian desde la
documentacion con nombre, tamano, SHA256 y uso.

## Mirrors

- MEGA:
  `https://mega.nz/folder/ZtwxCCJC#AIYHcTqz-ucjuzKnE9qD7A/folder/M9ZUTZQA`
- GitHub Release:
  `https://github.com/farhouse/cubieboard4-a80-debian12/releases/tag/external-images-2026-05`
- Johan Ahlberg, Cubieboard4:
  `https://sd-card-images.johang.se/boards/cubieboard4.html`

## Plan de preservacion

La estrategia usada es:

1. Mantener git solo para documentacion, DTB, logs, checksums y scripts.
2. Publicar imagenes como assets de una GitHub Release.
3. Mantener MEGA como mirror adicional.
4. Registrar siempre SHA256 para detectar corrupcion o reemplazos accidentales.

Release usada:

```text
external-images-2026-05
```

## Imagenes locales inventariadas

| Archivo | Tamano local | SHA256 | Uso |
|---|---:|---|---|
| `boot-cubieboard4.bin.gz` | 293 KiB | `768d66822c61534083330951a4c6ce21493a892596f5a1fb86bef692ccda1411` | Boot/U-Boot base usado en validacion original |
| `debian-bookworm-armhf-vim3ve.bin.gz` | 143 MiB | `f9bc8b5e61599d4a680eca63ddd09dcde5392ba5161325e1031eef9b574adffb` | Debian 12 armhf usado en validacion original |
| `android4.4-cb4-emmc-v4.3.20170717.img.7z` | 397 MiB | `42a2d8948a8971729b798cb1153cf3e724693566859d991e3e5d6c13d2517942` | Imagen vendor Android; fuente de blobs/firmware PowerVR/AP6330 |
| `linaro-desktop-cb4-emmc-hdmi-v1.1.img.7z` | 708 MiB | `dc4620fb27f72ad4b14c305287e9625d5534161499f7d485d8be557e3d480ac3` | Imagen Linaro/vendor; referencia de firmware y userspace |
| `cb4-debian-server-hdmi-card-v1.0.img.7z` | 277 MiB | `8af6f75dffa4b215fa40e254365f54de89510a2c0934b5ab4ac61e441eada3f5` | Imagen Debian vendor para SD/card |
| `cb4-debian-server-hdmi-emmc-v1.0.img.7z` | 346 MiB | `add542ead33e52495f847720dfe02f9f757dd2d1bbbabb7512a035a39f403d1f` | Imagen Debian vendor para eMMC |

## SHA256SUMS

```text
768d66822c61534083330951a4c6ce21493a892596f5a1fb86bef692ccda1411  boot-cubieboard4.bin.gz
f9bc8b5e61599d4a680eca63ddd09dcde5392ba5161325e1031eef9b574adffb  debian-bookworm-armhf-vim3ve.bin.gz
42a2d8948a8971729b798cb1153cf3e724693566859d991e3e5d6c13d2517942  android4.4-cb4-emmc-v4.3.20170717.img.7z
dc4620fb27f72ad4b14c305287e9625d5534161499f7d485d8be557e3d480ac3  linaro-desktop-cb4-emmc-hdmi-v1.1.img.7z
8af6f75dffa4b215fa40e254365f54de89510a2c0934b5ab4ac61e441eada3f5  cb4-debian-server-hdmi-card-v1.0.img.7z
add542ead33e52495f847720dfe02f9f757dd2d1bbbabb7512a035a39f403d1f  cb4-debian-server-hdmi-emmc-v1.0.img.7z
```

Para verificar descargas:

```sh
shasum -a 256 -c SHA256SUMS
```

## Uso desde scripts

El script [scripts/build-sd-image.sh](../scripts/build-sd-image.sh) usa la
GitHub Release `external-images-2026-05` como fuente reproducible por defecto.
Descarga y verifica:

- `boot-cubieboard4.bin.gz`
- `debian-bookworm-armhf-vim3ve.bin.gz`
- `cb4-debian-server-hdmi-card-v1.0.img.7z`, solo para extraer firmware AP6330

Compila el DTB desde `dts/sun9i-a80-cubieboard4.dts` (no lo descarga como
asset). Luego genera una imagen SD, instala el DTB compilado y copia:

- `fw_bcm40183b2_ag.bin` a `lib/firmware/brcm/brcmfmac4330-sdio.bin`
- `nvram_ap6330.txt` a `lib/firmware/brcm/brcmfmac4330-sdio.txt`

## Nota de licenciamiento

Las imagenes vendor pueden contener blobs y firmware propietarios. Se conservan
como referencia historica y de recuperacion para hardware discontinuado. El
repositorio git no redistribuye esos binarios directamente.
