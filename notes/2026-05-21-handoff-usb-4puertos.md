# Handoff: USB 4 puertos funcionales + boot automático

Fecha: 2026-05-21
Última modificación: 2026-05-21 20:38 (UTC-3)

## Resumen

Se compiló DTB definitivo con:
- `broken-cd` en mmc0 (boot automático desde SD sin parches RAM)
- `usbphy1` + `ehci0`/`ohci0` con `phy-supply = <&reg_usb1_vbus>` (PH14)
- `usbphy3` + `ehci2`/`ohci2` con `phy-supply = <&reg_usb2_vbus>` (PH15)
- `reg_usb0_vbus` (AXP GPIO1), `reg_usb1_vbus` (PH14), `reg_usb2_vbus` (PH15)
- mmc1 → SDIO 4-bit para AP6330 WiFi
- mmc2 → eMMC 8-bit

## Resultado

- Pendrive PHILIPS 62GB probado en los 4 puertos Type-A: todos funcionales.
- Boot automático desde `boot.scr` en `mmc 0:2`, sin intervención manual.
- DTB persistido en `/boot/sun9i-a80-cubieboard4.dtb` (25,293 bytes).
- DTB también disponible en FAT (`mmc 0:1`) como respaldo.

## Pendiente

- WiFi AP6330: `fatal err update clk timeout` / `brcmfmac_sdio_htclk: HT Avail timeout`

## Archivos clave

- DTS: `u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts`
- DTB: `dtb/sun9i-a80-cubieboard4.dtb`
- Matriz: `docs/boot/matriz-pruebas-arranque.md`
- Log: `logs/serial-live.log`
