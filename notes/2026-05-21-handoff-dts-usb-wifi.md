# Handoff: DTS fixes, USB parcial, WiFi pendiente

Fecha: 2026-05-21

## Resumen de logros

### Boot desde SD (nocd) ✅
- Parche `nocd`: renombrar `cd-gpios` → `xd-gpios` en DTB embebido de U-Boot.
- `mmc dev 0` ahora detecta la SD correctamente en U-Boot proper.

### Debian 12 Bookworm booteando ✅
- Kernel 6.1.0-37-armmp desde SD.
- Boot manual vía U-Boot con `root=/dev/mmcblk0p2` (evita PARTUUID conflict con eMMC).
- `boot.cmd` y `boot.scr` actualizados en `/boot/`.
- Ethernet (RTL8211E Gigabit) funcional.

### DTS corregido — mmc1 como SDIO WiFi ✅
- `mmc1` (1c10000) cambiado de eMMC 8-bit a SDIO 4-bit AP6330.
- `mmc2` (1c11000) mantiene eMMC 8-bit.
- Kernel asigna `mmc-pwrseq` correctamente.
- **Pendiente**: `fatal err update clk timeout` — el SDIO no se comunica con AP6330.

### DTS corregido — USB0 (OTG) habilitado ✅
- `ehci0`, `ohci0`, `usbphy1` con status "okay".
- `usb0_id_det-gpios = PH16` para detección de modo host.
- `reg_usb0_vbus`: regulador 5V vía AXP GPIO1, `regulator-always-on`.
- `reg_usb1_vbus`: regulador 5V vía PH14 para puertos Type A, `regulator-always-on`.
- Módulo `phy-sun9i-usb` agregado a `/etc/modules` para carga automática.
- **Pendiente**: hub interno 05e3:0608 detectado pero sin dispositivos downstream.

## Estado actual del DTS (archivo)

`u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts` con cambios:
- mmc1 → SDIO WiFi 4-bit (antes eMMC)
- usbphy1 → ID det + VBUS supply
- reg_usb0_vbus → AXP GPIO1, always-on
- reg_usb1_vbus → PH14, always-on

DTB compilado en `dtb/sun9i-a80-cubieboard4.dtb` y transferido a la CB4 en `/boot/`.

## Lo que NO funciona aún

### WiFi AP6330 ❌
```
sunxi-mmc 1c10000.mmc: fatal err update clk timeout
```
Posibles causas:
- Pin configuration inadecuada (PG0-PG5 con función "mmc1")
- Clock LPO del AC100 no configurado
- Regulador `vcc-io-wifi-codec-io2` (reg_cldo3): "voltage operation not allowed"
- Timing de power sequence incorrecto

### USB Type A (hub interno 05e3:0608) ❌
- Hub interno detectado en EHCI (4 puertos) pero sin dispositivos downstream.
- Reguladores VBUS enabled (usb0 y usb1).
- GPIO PH14 = out hi ✅.
- Próximo paso: probar conectando dispositivos directamente a diferentes puertos, verificar power cycling del hub.

### eMMC boot vs SD boot
- `root=PARTUUID=...` resuelve a la eMMC primero (mismo PARTUUID).
- Solución actual: `root=/dev/mmcblk0p2` en boot.cmd.

## Próximos pasos recomendados

1. **USB debug**: probar `echo 0 > /sys/bus/usb/devices/1-1/authorized && echo 1 > /sys/bus/usb/devices/1-1/authorized` para resetear hub, o desconectar/reconectar físicamente.
2. **WiFi SDIO**: ajustar drive-strength de mmc1_pins (30 → algo menor), verificar clock del AC100, o agregar `post-power-on-delay-ms` en wifi_pwrseq.
3. **DTB auto-carga**: hacer que U-Boot cargue el DTB desde ext4 automáticamente (ya configurado en boot.cmd).
4. **Documentar**: promover hallazgos validados de notes/ a docs/.

## Archivos clave

- `u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts` — DTS fuente
- `dtb/sun9i-a80-cubieboard4.dtb` — DTB compilado
- Imagen SD: `/private/tmp/cb4-bookworm/` (nocd variant)
- `u-boot/` — U-Boot 2025.04 johang build

## Serial

- Puerto: `/dev/cu.usbserial-14230`
- Config: 115200 8N1
- Comando: `picocom -b 115200 --databits 8 --parity n --stopbits 1 --flow n /dev/cu.usbserial-14230`
