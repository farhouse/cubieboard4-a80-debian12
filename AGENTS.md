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
Estabilizar el boot de Cubieboard4 A80 con Debian 12 desde microSD, lograr imagen reproducible, y resolver boot desde eMMC.

### Completed
- SD root UUID fix: `boot.scr` usaba `root=/dev/mmcblk0p2`, pero el orden `mmcblkN` es inestable con SD + eMMC + SDIO WiFi. Corregido a `root=UUID=...`, validado con boot automático hasta login Debian 12.
- `scripts/build-sd-image.sh`: builder reproducible para Linux que descarga assets desde GitHub Release, arma imagen concatenando boot+rootfs, instala DTB validado, firmware AP6330, y regenera `boot.scr` con `root=UUID=...`.
- `scripts/install-to-emmc.sh`: instalador conservador SD→eMMC con dry-run por defecto, backup obligatorio en USB, verificación de que el backup no esté en SD/eMMC, formato con `-E nodiscard` para evitar bloqueo, copia via rsync o tar fallback, y genera `boot.scr` para eMMC con `root=UUID=...`.
- Instalación Debian 12 a eMMC completada exitosamente (backup previo, rsync, boot.scr generado).
- DTB validado en `dtb/sun9i-a80-cubieboard4.dtb` con: `broken-cd` en mmc0, mmc1→AP6330 SDIO 4-bit, mmc2→eMMC 8-bit HS200, `phy-supply` en usbphy1/usbphy3, reguladores VBUS, `wifi_pwrseq`.
- Validación USB Type-A funcional en 4 puertos (hub `05e3:0608`).
- Validación WiFi AP6330 funcional (`wlan0`, BCM4330/4, HT 300 Mbps).
- README traducido a inglés y reestructurado alrededor de reproducción de imagen.
- Matriz de pruebas `docs/boot/matriz-pruebas-arranque.md` con 9 intentos documentados.
- `CONFIG_MMC_BROKEN_CD=y` agregado a `configs/Cubieboard4_defconfig`, compilado nativo en CB4, flasheado a eMMC boot partition.
- **eMMC boot sin SD: RESUELTO**. Root cause: `get_mclk_offset()` en `drivers/mmc/sunxi_mmc.c:649` chequeaba `CONFIG_MACH_SUN9I_A80` (no existe) en vez de `CONFIG_MACH_SUN9I`. U-Boot proper escribía clock register de MMC2 en `0x06000090` en vez de `0x06000418`, lo que corrompía CMD2. Fix: cambio de `SUN9I_A80` a `SUN9I`.

### Next Steps
1. **Reproducir imagen SD con builder**: correr `scripts/build-sd-image.sh` en una máquina Linux o VM Linux, grabar a SD limpia y validar boot automático.
2. **Bluetooth AP6330**: instalar `bcm40183b2.hcd` y configurar UART/GPIOs BT.
3. **HDMI/VGA**: probar salida de video.
4. **Reconstruir DTS source** correspondiente al DTB final.
5. **GPU/display** (postergado): PowerVR G6230 sin firmware público para BVNC 1.75.2.30; HDMI no declarado en DTS mainline.
6. **Enviar patch upstream**: typo `CONFIG_MACH_SUN9I_A80` afecta todos los sun9i-A80.

### Key Reference Files
- `dtb/sun9i-a80-cubieboard4.dtb` — DTB final validado.
- `scripts/build-sd-image.sh` — builder reproducible.
- `scripts/install-to-emmc.sh` — instalador eMMC.
- `docs/boot/matriz-pruebas-arranque.md` — matriz cronológica de pruebas.
- `docs/estado-validado.md` — estado consolidado de subsistemas.
- `notes/2026-05-25-handoff-sd-root-uuid-emmc-blocker.md` — handoff con análisis de ambos issues.
- `notes/2026-05-25-sd-initramfs-root-device-name.md` — detalle del fix root UUID.
- `notes/2026-05-25-emmc-debian12-install-uboot-blocker.md` — detalle del blocker eMMC.
- `notes/2026-05-25-handoff-mmc-broken-cd-build-test.md` — handoff build/test CONFIG_MMC_BROKEN_CD.
- `notes/2026-05-26-emmc-boot-fix-clock-register.md` — detalle del fix clock register.
- `docs/kernel/gpu-opencl-opengl-plan.md` — plan GPU/display (investigación previa, no activa).
