# Especificaciones — Cubieboard4 (CC-A80)

> Documento de referencia rápida para el proyecto de revive.
> Estado: **borrador inicial**, validar contra fuentes oficiales y la placa física.

## Resumen

- **Placa:** Cubieboard4 (también referida como **CC-A80**)
- **SoC:** Allwinner A80
- **CPU:** arquitectura big.LITTLE
  - 4× ARM Cortex-A15
  - 4× ARM Cortex-A7
- **GPU:** PowerVR G6230 (Rogue)
- **RAM:** 2 GB (integrada)
- **Almacenamiento interno:** 8 GB (integrado)

## Capacidades multimedia (reportadas)

- Soporte de motor de display con foco en codecs modernos para su generación
- Referencias públicas mencionan soporte de:
  - H.265
  - resolución 4K
  - salida simultánea en múltiples pantallas

> ⚠️ Estas capacidades dependen de drivers, stack de kernel y soporte real en la distro usada.

## Conectividad / I/O

- Puerto OTG microUSB 3.0 (mencionado en referencias)
- USB Type-A: cuatro puertos validados mediante el hub interno `05e3:0608`.
- WiFi AP6330: asociación, DHCP, DNS e Internet validados.
- Ethernet RTL8211E: link Gigabit Full Duplex, sin tráfico validado.
- Salidas de video y resto de periféricos: **validar según revisión exacta de placa + documentación del fabricante**.

## Sistema operativo objetivo (para revive)

Para este proyecto conviene priorizar:
1. Boot estable
2. Serial funcional
3. eMMC/SD confiables
4. Red funcional
5. Ajuste de DTS/DTB por compatibilidad

## Notas de validación práctica

Checklist mínimo en laboratorio:
- [ ] Confirmar modelo exacto serigrafiado en placa
- [x] Confirmar capacidad de RAM visible por sistema (2 GiB)
- [x] Confirmar eMMC detectada y tamaño real
- [x] Confirmar salida serial durante boot (`115200 8N1`)
- [x] Confirmar migracion/boot de Debian 12 desde eMMC

## Fuentes consultadas (iniciales)

- Wikipedia — Cubieboard (sección Cubieboard4/CC-A80)
  - https://en.wikipedia.org/wiki/Cubieboard

---

## Ampliaciones de referencia

Completar este archivo con:
- enlaces oficiales del fabricante (si siguen disponibles),
- snapshots/archivos archivados confiables,
- resultados medidos en la placa real durante el bring-up.

Los trabajos activos se mantienen en
[`../pendientes-implementacion.md`](../pendientes-implementacion.md).
