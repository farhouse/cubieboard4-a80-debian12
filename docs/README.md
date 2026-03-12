# Docs

Carpeta para recopilar información relevante del proyecto de revive de la Cubieboard4 A80.

## Qué guardar acá

- Datasheets y referencias técnicas resumidas
- Notas de hardware (pines, alimentación, serial, eMMC/SD)
- Guías de bootloader/kernel/DTB aplicables
- Troubleshooting y fixes validados
- Decisiones técnicas consolidadas (versiones, herramientas, estrategia)

## Sugerencia de organización

- `hardware/` → placa, pines, alimentación, serial
- `boot/` → u-boot, arranque, secuencia de boot
- `kernel/` → versiones, configs, parches
- `device-tree/` → referencias DTS/DTB
- `troubleshooting/` → errores comunes y resolución

> Tip: cuando una nota en `notes/` ya está validada y estable, promoverla acá como documentación durable.
