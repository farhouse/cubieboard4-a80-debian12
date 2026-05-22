# Matriz de pruebas de arranque — Cubieboard4 A80

> Usar este documento para llevar control reproducible de qué combinaciones arrancan y cuáles fallan.

## Objetivo

Registrar cada intento de boot con contexto suficiente para:
- repetir pruebas,
- comparar resultados,
- detectar regresiones,
- priorizar próximos pasos.

## Convención de evidencia

- Logs: `logs/YYYY-MM-DD-<tema>.log`
- Notas: `notes/YYYY-MM-DD-<tema>.md`
- Parches: `patches/YYYY-MM-DD-<tema>.patch`

## Matriz

| Fecha | Imagen / Distro | Kernel | U-Boot | Medio (eMMC/SD) | DTB/DTS | Estado | Tiempo hasta consola | Resultado breve | Evidencia |
|---|---|---|---|---|---|---|---|---|---|
| 2026-05-21 | Bookworm SD + boot-cubieboard4 | 6.1.0-37-armmp | 2025.04 johang | microSD | sun9i-a80-cubieboard4 (U-Boot stock) | ✅ OK | ~35s | Boot completo hasta login. mmc0 detectado tras parche nocd | `notes/2026-05-21-handoff-bookworm-sd-uboot.md` |
| 2026-05-21 | Bookworm SD (DTS propio) | 6.1.0-37-armmp | 2025.04 johang | microSD | sun9i-a80-cubieboard4 (DTS editado) | ✅ OK | ~35s | USB0 habilitado, mmc1→SDIO, mmc2→eMMC. WiFi clock timeout | `notes/2026-05-21-handoff-dts-usb-wifi.md` |
| 2026-05-21 | Bookworm SD (USB phy-supply) | 6.1.0-37-armmp | 2025.04 johang | microSD | sun9i-a80-cubieboard4 (`phy-supply`) | ✅ OK | ~35s | USB Type-A funcional: teclado Logitech enumera detras del hub 05e3:0608 | `notes/2026-05-21-handoff-usb-typea.md` |
| 2026-05-21 | Bookworm SD (broken-cd en RAM) | 6.1.0-37-armmp | 2025.04 johang | microSD + eMMC | sun9i-a80-cubieboard4 (`broken-cd`) | ⚠️ PARCIAL | ~35s | En initramfs Linux ve la SD como `mmcblk0` y la eMMC como `mmcblk1`; falta persistir el DTB en la SD | `notes/2026-05-21-handoff-sd-usb-final.md` |
| 2026-05-21 | Bookworm SD (DTB definitivo, USB 4 puertos) | 6.1.0-37-armmp | 2025.04 johang | microSD | sun9i-a80-cubieboard4 (`dtb/` compilado) | ✅ OK | ~35s | Boot completo. USB Type-A funcional en los 4 puertos. `broken-cd` persistente en mmc0. | `logs/serial-live.log` |
| 2026-05-22 | Bookworm SD (WiFi AP6330) | 6.1.0-37-armmp | 2025.04 johang | microSD | sun9i-a80-cubieboard4 (WiFi fixes + firmware) | ✅ OK | ~35s | WiFi AP6330 funcional (wlan0): `ifconfig wlan0 up` + `iw dev wlan0 scan` OK, HT hasta 300 Mbps. | `logs/2026-05-22-final-wifi-validation.log` |

## Criterios de estado

- ✅ **OK**: arranca completo hasta login/shell usable.
- ⚠️ **Parcial**: avanza pero queda bloqueado en etapa intermedia.
- ❌ **Fail**: no hay progreso útil (sin salida serial, reset temprano, etc.).

## Checklist por corrida

- [ ] Confirmé alimentación estable.
- [ ] Guardé log serial completo.
- [ ] Registré hash/nombre exacto de imagen.
- [ ] Registré versión de kernel y u-boot.
- [ ] Registré DTB usado.
- [ ] Enlacé evidencia en la matriz.

## Top causas a observar

1. DRAM init / training.
2. Problemas de eMMC/SD (detección o rootfs).
3. DTB incompatible con revisión de placa.
4. Diferencias de U-Boot entre imágenes.
5. Fuente insuficiente / inestable.

## Próximo paso recomendado

Completar al menos **3 corridas comparables** (misma imagen + distinto DTB o medio) para tener línea base.
