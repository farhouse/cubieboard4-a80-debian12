# Handoff final: CB4 revive — USB + WiFi + boot completo

Fecha: 2026-05-22
Última modificación: 2026-05-22 18:32 (UTC-3)

## Estado del sistema

Cubieboard4 A80 booteando Debian 12 Bookworm desde microSD con:

| Subsistema | Estado | Detalle |
|---|---|---|
| Boot SD | ✅ | `broken-cd` en mmc0, automático vía `boot.scr` |
| USB Type-A (4 puertos) | ✅ | Hub 05e3:0608, `usbphy1` + `usbphy3` con `phy-supply` |
| Ethernet RTL8211E | ✅ | Gigabit Full Duplex |
| WiFi AP6330 | ✅ | wlan0, BCM4330/4, scan funcional hasta 300 Mbps |
| Bluetooth | ⏳ Pendiente | `bcm40183b2.hcd` disponible, falta configurar |

## Cambios realizados

### DTS (`u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts`)

1. **mmc0**: `cd-gpios` → `broken-cd` (boot desde SD)
2. **mmc1**: SDIO 4-bit para AP6330, `no-1-8-v`, `drive-strength` reducido a 0x14
3. **mmc2**: eMMC 8-bit (sin cambios)
4. **USB**: `usbphy1` + `ehci0/ohci0` con `reg_usb1_vbus` (PH14)
5. **USB**: `usbphy3` + `ehci2/ohci2` con `reg_usb2_vbus` (PH15)
6. **USB**: `reg_usb0_vbus` (AXP GPIO1) para OTG
7. **WiFi**: `post-power-on-delay-ms = <50>` en wifi_pwrseq
8. **WiFi**: `reg_ldoio0` via `axp_gpio 0` (wifi_power_ext2 del FEX vendor)

### Firmware

Firmwares AP6330 extraídos de imagen vendor e instalados en:
- `/lib/firmware/brcm/brcmfmac4330-sdio.bin` (239,507 bytes)
- `/lib/firmware/brcm/brcmfmac4330-sdio.txt` (nvram)

### DTB

Compilado en `dtb/sun9i-a80-cubieboard4.dtb` (25,505 bytes) y persistido en `/boot/` de la SD.

## Comandos de prueba

```sh
# Verificar WiFi
ifconfig wlan0 up
iw dev wlan0 scan

# Verificar USB
lsusb
cat /sys/kernel/debug/usb/devices

# Verificar MMC
cat /proc/partitions
```

## Pendiente

1. **Bluetooth**: instalar `bcm40183b2.hcd` en `/lib/firmware/brcm/`
2. **wpasupplicant**: instalar para conectarse a redes WiFi
3. **eMMC boot**: probar si se puede bootear desde la eMMC
4. **HDMI/VGA**: display output no probado

## Commits

```
fd6b4e7 docs(boot): add boot test matrix template
f0989bf feat(usb): enable all 4 Type-A ports and fix SD boot with broken-cd
abd0c25 feat(wifi): enable AP6330 SDIO WiFi with vendor firmware
```
