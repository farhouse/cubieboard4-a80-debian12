# Cubieboard4 A80 Revive

Repositorio de trabajo para revivir y documentar una **Cubieboard4 / CC-A80
(Allwinner A80)** con kernel mainline.

La prioridad del repo es dejar evidencia reproducible: que se probo, con que
imagen/DTB/kernel, que funciono, que no funciono y que queda pendiente. Esto no
es una distribucion ni un SDK completo.

## Objetivo

Recuperar un entorno booteable y mantenible para la placa, dejando trazabilidad
de:

- cambios en device tree,
- imagenes probadas,
- parches aplicados,
- resultados de pruebas.

## Estado actual

Resumen validado al 2026-05-22:

- Debian 12 Bookworm armhf bootea desde microSD.
- Kernel probado: `6.1.0-37-armmp`.
- U-Boot probado: `2025.04johang-dirty`.
- Ethernet RTL8211E funciona.
- USB Type-A funciona en los 4 puertos via hub interno.
- WiFi AP6330 funciona y escanea redes.
- eMMC se detecta; boot desde eMMC sigue pendiente.
- VGA/HDMI siguen pendientes de validacion en hardware.
- GPU PowerVR G6230 no tiene aceleracion mainline viable hoy por falta de
  firmware publico para BVNC `1.75.2.30`.

Ver [docs/estado-validado.md](docs/estado-validado.md) para el detalle tecnico
y la evidencia asociada.

## Estructura

- `dts/` → fuentes Device Tree (`.dts`, `.dtsi`).
- `dtb/` → binarios compilados (`.dtb`) listos para test.
- `images/` → imágenes base o referencias usadas en pruebas.
- `patches/` → parches aplicados (kernel/u-boot/device-tree).
- `logs/` → logs de arranque, consola, errores y resultados.
- `notes/` → notas técnicas, hipótesis y decisiones.
- `docs/` → documentos consolidados y referencias durables.

## Contenido no incluido

El repositorio evita subir imagenes completas, dumps, arboles vendor y manuales
copiados. En su lugar se documentan nombres, origenes, hashes cuando aplica y
referencias externas.

Quedan ignorados por defecto:

- `images/*.img`, `images/*.7z`, `images/*.bin.gz`
- arboles locales como `u-boot/` o kernels vendor
- PDFs/manuales A80 descargados localmente
- logs seriales vivos o temporales

Ver [docs/referencias-a80.md](docs/referencias-a80.md) para enlaces tecnicos
externos usados durante la investigacion.

## Workflow recomendado

1. Registrar hipótesis en `notes/`.
2. Aplicar cambio (DTS/patch/config).
3. Ejecutar prueba.
4. Guardar evidencia en `logs/`.
5. Si sirve, dejar patch en `patches/` y resumen en notas.

## Convenciones

- `logs/YYYY-MM-DD-<tema>.log`
- `notes/YYYY-MM-DD-<tema>.md`
- `patches/YYYY-MM-DD-<tema>.patch`
- Mensajes de commit claros y atómicos.

## Próximos pasos

1. Correr inventario GPU/display en la placa real: `dmesg`, `ls /dev/dri`,
   `lsmod`, `modetest -c`, `glxinfo -B`.
2. Probar VGA con `modetest -M sun4i-drm -c`.
3. Investigar HDMI contra el manual A80 y el driver vendor 3.4.
4. Documentar boot desde eMMC si queda validado.
