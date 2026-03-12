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

## Conectividad / I/O (a validar en placa)

- Puerto OTG microUSB 3.0 (mencionado en referencias)
- Salidas de video y resto de periféricos: **validar según revisión exacta de placa + documentación del fabricante**

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
- [ ] Confirmar capacidad de RAM visible por sistema
- [ ] Confirmar eMMC detectada y tamaño real
- [ ] Confirmar salida serial durante boot
- [ ] Confirmar boot desde medio seleccionado (eMMC/SD)

## Fuentes consultadas (iniciales)

- Wikipedia — Cubieboard (sección Cubieboard4/CC-A80)
  - https://en.wikipedia.org/wiki/Cubieboard

---

## Pendiente recomendado

Completar este archivo con:
- enlaces oficiales del fabricante (si siguen disponibles),
- snapshots/archivos archivados confiables,
- resultados medidos en la placa real durante el bring-up.
