# Handoff: SD Bookworm, USB Type-A y `broken-cd`

Fecha: 2026-05-21

## Estado general

La línea de trabajo ya cerró el punto más importante:

- La microSD con Debian 12 Bookworm existe y U-Boot la lee como `mmc 0:2`.
- El rootfs Bookworm se identificó desde U-Boot con `PARTUUID=800e6fd4-02` y `os-release` muestra `Debian GNU/Linux 12 (bookworm)`.
- El problema de arranque en Linux no era la imagen, sino la detección de card-detect en `mmc0`.
- Cuando se fuerza `broken-cd` en el FDT de `mmc0`, Linux enumera la SD como `mmcblk0` y la eMMC como `mmcblk1`.

## Hallazgo clave

En el DTS de `u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts`, el nodo original de la SD tenía:

```dts
&mmc0 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc0_pins>;
	vmmc-supply = <&reg_dcdc1>;
	bus-width = <4>;
	cd-gpios = <&pio 7 18 GPIO_ACTIVE_LOW>; /* PH18 */
	status = "okay";
};
```

La prueba que destrabó el boot fue cambiar ese detect por:

```dts
broken-cd;
```

No fue necesario persistir el cambio para validar el mecanismo: se aplicó primero en el FDT cargado en RAM desde U-Boot y Linux pasó a ver:

- `mmc0` = SD (`SD8GB`, `7.42 GiB`)
- `mmc1` = eMMC (`NCard`, `7.30 GiB`)

## Resultado de la prueba en Linux

Con `broken-cd` en el FDT activo:

- `mmc0: new high speed SDHC card`
- `mmcblk0: mmc0:0007 SD8GB 7.42 GiB`
- `mmcblk0: p1 p2`
- `mmc1: new DDR MMC card`
- `mmcblk1: mmc1:0001 NCard 7.30 GiB`

Eso confirma que la microSD sí bootea en Linux cuando se elimina la dependencia del GPIO de detect.

## USB Type-A

El fix de USB quedó validado y sigue siendo el correcto:

```dts
&usbphy1 {
	phy-supply = <&reg_usb1_vbus>;
	status = "okay";
};
```

Con eso, el hub interno `05e3:0608` enumera downstream y se verificó:

- teclado Logitech TKL como HID
- pendrive como `usb-storage` / `sda`

El puerto funcional observado fue el downstream del hub en `2-1.1` / `3-1.1` según la numeración del boot.

## Lo que sigue pendiente

1. Persistir el DTB corregido en la SD, no solo en el FDT de RAM.
2. Confirmar un boot completo de Bookworm desde la microSD con `broken-cd` permanente.
3. Seguir con el mapeo de los puertos USB restantes; por ahora quedó claro que el bloque Type-A asociado a `usbphy1` funciona, pero no se validó cada puerto físico por separado.
4. Mantener como pendiente el WiFi AP6330: `sunxi-mmc 1c10000.mmc: fatal err update clk timeout`.

## Archivos relevantes

- [`u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts`](/Users/farhouse/Projects/cubieboard4-a80-revive/u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts)
- [`dtb/sun9i-a80-cubieboard4.dtb`](/Users/farhouse/Projects/cubieboard4-a80-revive/dtb/sun9i-a80-cubieboard4.dtb)
- [`notes/2026-05-21-handoff-bookworm-sd-uboot.md`](/Users/farhouse/Projects/cubieboard4-a80-revive/notes/2026-05-21-handoff-bookworm-sd-uboot.md)
- [`notes/2026-05-21-handoff-usb-typea.md`](/Users/farhouse/Projects/cubieboard4-a80-revive/notes/2026-05-21-handoff-usb-typea.md)
- [`notes/2026-05-21-handoff-dts-usb-wifi.md`](/Users/farhouse/Projects/cubieboard4-a80-revive/notes/2026-05-21-handoff-dts-usb-wifi.md)

## Resumen corto

La SD Bookworm ya está localizada y el root cause quedó aislado: `cd-gpios` en `mmc0`. Con `broken-cd`, el arranque por SD es viable y la enumeración de bloques cambia como esperábamos. USB Type-A ya funciona con `phy-supply` en `usbphy1`.
