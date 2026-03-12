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
| _(ej)_ 2026-03-12 | Armbian nightly | 6.6.x | 2024.xx | microSD | sunxi-a80-*.dtb | ⚠️ Parcial | 12s | Llega a U-Boot, no monta rootfs | `logs/2026-03-12-boot-armbian.log` |
|  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |

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
