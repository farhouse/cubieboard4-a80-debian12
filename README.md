# Cubieboard4 A80 Revive

Repositorio de trabajo para revivir y estabilizar una **Cubieboard4 (Allwinner A80)**.

## Objetivo

Recuperar un entorno booteable y mantenible para la placa, dejando trazabilidad de:
- cambios en device tree,
- imágenes probadas,
- parches aplicados,
- resultados de pruebas.

## Alcance (por ahora)

- Boot básico y validación de arranque.
- Iteración sobre DTS/DTB.
- Pruebas con imágenes y variantes de kernel/bootloader.
- Registro técnico en notas/logs para reproducibilidad.

## Estructura

- `dts/` → fuentes Device Tree (`.dts`, `.dtsi`).
- `dtb/` → binarios compilados (`.dtb`) listos para test.
- `images/` → imágenes base o referencias usadas en pruebas.
- `patches/` → parches aplicados (kernel/u-boot/device-tree).
- `logs/` → logs de arranque, consola, errores y resultados.
- `notes/` → notas técnicas, hipótesis y decisiones.

## Estado actual

- [x] Repositorio inicializado.
- [ ] Definir baseline de imagen/bootloader para pruebas.
- [ ] Primera corrida documentada de arranque (éxito o fallo).
- [ ] Identificar bloqueante principal actual (si no bootea).

## Workflow recomendado

1. Registrar hipótesis en `notes/`.
2. Aplicar cambio (DTS/patch/config).
3. Ejecutar prueba.
4. Guardar evidencia en `logs/`.
5. Si sirve, dejar patch en `patches/` y resumen en notas.

## Convenciones sugeridas

- `logs/YYYY-MM-DD-<tema>.log`
- `notes/YYYY-MM-DD-<tema>.md`
- `patches/YYYY-MM-DD-<tema>.patch`
- Mensajes de commit claros y atómicos.

## Próximos pasos

1. Documentar hardware exacto y método de acceso serial.
2. Elegir imagen baseline para primer test reproducible.
3. Registrar secuencia de booteo inicial completa.
4. Priorizar fixes (power, DRAM, MMC/eMMC, red, video) según impacto.
