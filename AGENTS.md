# Repository Guidelines

## Project Structure & Module Organization

This repository tracks the revive workflow for a Cubieboard4 A80 board. It is documentation- and evidence-first rather than an application codebase.

- `dts/`: Device Tree sources (`.dts`, `.dtsi`) under active iteration.
- `dtb/`: compiled Device Tree blobs (`.dtb`) used for board tests.
- `images/`: baseline OS, bootloader, or recovery images and image references.
- `patches/`: patch files for kernel, U-Boot, or device tree changes.
- `logs/`: serial console captures, boot output, errors, and test evidence.
- `notes/`: working notes, hypotheses, and decisions during investigation.
- `docs/`: durable references promoted from validated notes, organized by `hardware/`, `boot/`, `kernel/`, `device-tree/`, and `troubleshooting/`.

## Build, Test, and Development Commands

There is no project-wide build script yet. Use tool-specific commands and record exact invocations in notes or logs.

- `dtc -I dts -O dtb -o dtb/<name>.dtb dts/<name>.dts`: compile a Device Tree source for testing.
- `git diff -- dts/ patches/ docs/`: review technical changes before committing.
- `git status --short`: check for generated files, logs, and notes that should be included or ignored.

If a command depends on a host tool version, record it with the test notes, for example `dtc --version` or `u-boot` source revision.

## Coding Style & Naming Conventions

Keep Markdown direct and reproducible. Prefer short sections, command examples, and dated evidence. Use Spanish or English consistently within each file; existing project docs are mostly Spanish.

Follow the repository naming patterns:

- `logs/YYYY-MM-DD-<topic>.log`
- `notes/YYYY-MM-DD-<topic>.md`
- `patches/YYYY-MM-DD-<topic>.patch`

For DTS files, use board- or variant-specific names and keep generated `.dtb` files in `dtb/`, not beside sources.

## Testing Guidelines

Testing is hardware validation. For each boot attempt, capture the baseline image or bootloader, DTS/DTB version, power and serial setup, observed result, and full serial log. Store raw output in `logs/` and summarize the conclusion in `notes/` or `docs/boot/matriz-pruebas-arranque.md`.

Promote only validated, stable findings from `notes/` into `docs/`.

## Commit & Pull Request Guidelines

Git history uses concise conventional-style commits such as `docs(boot): add boot test matrix template` and `chore: initialize repository with project structure`. Keep commits atomic and scoped to one artifact or finding.

Pull requests should include the goal, changed files, hardware or image baseline tested, relevant log paths, and any unresolved risks. Link issues when available and include screenshots only for visual hardware evidence or UI tooling.

## Current Session Progress

### Goal
Investigar y documentar el soporte de GPU (PowerVR G6230), display (sun4i-drm), y documentación técnica del SoC A80 para Cubieboard4 en kernel mainline 6.1.

### Completed
- Analizado plan existente `docs/kernel/gpu-opencl-opengl-plan.md` (~300 lineas iniciales).
- Investigacion upstream: sun4i-drm soporta A80 desde kernel 4.18 (parches Chen-Yu Tsai 2018). DTS `sun9i-a80.dtsi` declara pipeline completo (FE0/FE1, BE0/BE1, DEU0/DEU1, DRC0/DRC1, TCON0 para LCD/VGA, TCON1 para HDMI/sin nodo).
- HDMI **no declarado** en DTS mainline; requiere investigacion sobre compatibilidad con sun6i-hdmi (A31).
- PowerVR G6230 **no soportado** por driver abierto `drm/imagination`. Driver soporta AXE-1-16M, BXS-4-64, BXM-4-64. GX6250 (Series6XT) tiene soporte parcial en Mesa (parches Google 2024) pero aun no upstream en DRM kernel. G6230 ni siquiera aparece como "unsupported" en las tablas Mesa.
- BVNC confirmado: **1.75.2.30** (Rogue Series6, dual-cluster 64 cores) del Makefile vendor `CC-A80-kernel-source/modules/rogue_km/`.
- No hay firmware publico para BVNC 1.75.2.30. El mas cercano es GX6250 (4.40.2.51).
- OpenCL **excluido** en build vendor (`EXCLUDED_APIS = opencl`). Modulos vendor: `pvrsrvkm.ko` + `dc_drmfbdev.ko` para kernel 3.4. Port a 6.1 inviable sin reescritura completa.
- Vendor stack display usa drivers propietarios Allwinner (`drivers/video/sunxi/disp/`, `drivers/video/sunxi/hdmi/`), sin Device Tree (`CONFIG_USE_OF` desactivado).
- Documento `gpu-opencl-opengl-plan.md` actualizado a ~500 lineas (v3).
- Datasheet A80 v1.0 encontrado en `http://dl.linux-sunxi.org/A80/A80_Datasheet_Revision_1.0_0404.pdf` (accesible, 43 pag).
- **A80 Datasheet v1.3** (2015-05-10, mas reciente encontrado) en `https://github.com/allwinner-zh/documents/raw/master/A80/A80_Datasheet_v1.3_20150510.pdf`
- **A80 User Manual v1.3.1** (1056 paginas, 2015-05-13) encontrado en GitHub.
- Meta-sunxi/Yocto: Leon Anavi bootea Merrii A80 Optimus con kernel 6.6.28 + U-Boot 2024.10 (display no verificado).
- **Analisis profundo arquitectura driver DRM**: el kernel NO necesita arquitectura nueva (es BVNC-agnostico, features vienen del firmware). Solo ~5 lineas de cambio. Mesa si requiere nueva tabla device_info y posiblemente archivos `pvr_arch_rogue6.*`.
- **Extraccion de imagenes vendor completada**: Android 4.4 contiene `pvrsrvkm.ko`, `libGLESv1_CM_POWERVR_ROGUE.so`, `libGLESv2_POWERVR_ROGUE.so`, `libPVROCL.so`. Todos dependientes de kernel 3.4. Linaro contiene solo userspace DRI/GLES.
- **Blobs vendor confirmados incompatibles** con mainline: firmware usa interfaz pvrsrvkm vieja, no FWIF moderna. Imagination debe recompilar firmware nuevo para BVNC 1.75.2.30.
- **Confirmado el unico blocker real es el firmware**: sin `rogue_1.75.2.30_v1.fw` con `PVR_FW_FLAGS_OPEN_SOURCE`, el driver rechaza la GPU. No se puede parchear, espoofear, ni extraer del vendor.

### Blocked
- GPU acelerada mainline: solo posible si Imagination libera firmware para BVNC 1.75.2.30 y agrega soporte en driver abierto. El precedente GX6250 (Google/Chromebook) confirma que Imagination provee firmware a partners con interes comercial. Sin partner para A80, es improbable.
- Diferencia Series6 vs Series6XT: significativa (hasta 50% mas rapido 6XT). El driver abierto se diseno para Series6XT+, agregar Series6 requeriria cambios arquitectonicos (`pvr_arch_*.c`).
- Firmware publico en linux-firmware.git: `rogue_33.15.11.3_v1.fw`, `rogue_36.53.104.796_v1.fw`, `rogue_4.40.2.51_v1.fw`, `rogue_36.52.104.182_v1.fw`. Ninguno para BVNC 1.75.2.30.
- OpenCL: excluido en vendor, no hay blobs compilados para A80. Requeriría reimplementación completa.
- No se han localizado imágenes Linaro/Android funcionales para extraer blobs PowerVR userspace.

### Next Steps
1. **Ejecutar inventario** en CB4 real: `dmesg`, `ls /dev/dri`, `lsmod`, `modetest -c`, `glxinfo -B`; guardar en `logs/YYYY-MM-DD-gpu-display-inventory.log`.
2. **Probar VGA** (Fase 2): conectar monitor VGA, correr `modetest -M sun4i-drm -c`, probar modos de video.
3. **Descargar A80 User Manual v1.3.1** localmente desde GitHub raw para consulta offline.
4. ~~**Buscar imágenes vendor** (Linaro/Android) para extraer blobs PowerVR userspace (libEGL, libGLES, pvrsrvctl).~~ **COMPLETADO** -- blobs localizados en imagen Android. Incompatibles con mainline.
5. **Investigar HDMI**: revisar A80 User Manual para determinar si el controller HDMI comparte diseño con A31 (sun6i-hdmi).

### Key Reference Files
- `docs/kernel/gpu-opencl-opengl-plan.md` — plan principal con hallazgos actualizados.
- `u-boot/arch/arm/dts/sun9i-a80.dtsi` — DTS SoC con pipeline display, sin GPU ni HDMI.
- `u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts` — DTS placa, habilita `&de`, VGA via tcon0.
- `https://github.com/cubieboard/CC-A80-kernel-source` — kernel vendor 3.4 con PowerVR Rogue DDK, BVNC 1.75.2.30.
- `https://github.com/allwinner-zh/documents/tree/master/A80` — A80 Datasheet v1.3 + User Manual v1.3.1.
- `https://dl.linux-sunxi.org/SDK/A80/` — SDK stripped browseable.
- `images/android4.4-cb4-emmc-v4.3.20170717.img.7z` — Imagen Android con pvrsrvkm.ko, libGLES_POWERVR_ROGUE, libPVROCL.
