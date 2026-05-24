# Imagenes de prueba

Esta carpeta se usa como referencia local para imagenes de sistema, bootloader
o recuperacion usadas durante las pruebas de Cubieboard4 A80.

Las imagenes completas no se versionan en git por tamano y por posibles
restricciones de licencia. Para cada imagen usada en una prueba, registrar en
`notes/` o `logs/`:

- nombre de archivo;
- URL u origen exacto;
- fecha de descarga;
- hash (`sha256sum` o equivalente);
- particiones o offsets relevantes;
- resultado observado en hardware.

Nombres mencionados por la investigacion actual:

- `android4.4-cb4-emmc-v4.3.20170717.img.7z`
- `linaro-desktop-cb4-emmc-hdmi-v1.1.img.7z`
- `cb4-debian-server-hdmi-card-v1.0.img.7z`
- `cb4-debian-server-hdmi-emmc-v1.0.img.7z`
- `debian-bookworm-armhf-vim3ve.bin.gz`
- `boot-cubieboard4.bin.gz`
