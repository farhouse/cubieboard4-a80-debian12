# Handoff: USB Type-A funcional tras `phy-supply`

Fecha: 2026-05-21

## Resumen

El hub interno `05e3:0608` (USB2.0 Hub, 4 puertos) se detectaba correctamente en EHCI (`a00000.usb`, Bus 01), pero inicialmente no enumeraba dispositivos downstream.

El cambio efectivo fue conectar el supply correcto al PHY A80:

```dts
&usbphy1 {
	phy-supply = <&reg_usb1_vbus>;
	status = "okay";
};
```

Con ese DTB, un teclado Logitech conectado a Type-A enumera como HID:

```text
input: Logitech Logi TKL Mechanical Keyboard as /devices/platform/soc@20000/a00000.usb/usb2/2-1/2-1.1/...
hid-generic 0003:046D:C345.0002: input,hidraw1: USB HID v1.11 Keyboard [Logitech Logi TKL Mechanical Keyboard] on usb-a00000.usb-1.1/input1
hid-generic 0003:046D:C345.0003: hiddev0,hidraw2: USB HID v1.11 Device [Logitech Logi TKL Mechanical Keyboard] on usb-a00000.usb-1.1/input2
```

## Estado actual del sistema

### Boot
- Debian 12 Bookworm, kernel 6.1.0-37-armmp
- U-Boot 2025.04 johang
- SD boot con parche `nocd` (cd-gpios → xd-gpios)
- Ethernet funcional (RTL8211E Gigabit)

### USB detectado antes del fix
```
Bus 01 (EHCI a00000.usb):
  └── 1-1: 05e3:0608 USB2.0 Hub (4 puertos, bus-powered, 100mA)
        ├── port1: unknown, over_current=0
        ├── port2: unknown, over_current=0
        ├── port3: unknown, over_current=0
        └── port4: unknown, over_current=0

Bus 02 (OHCI a00400.usb):
  └── (sin dispositivos)
```

### Reguladores VBUS
```
gpio-238 (usb1-vbus) out hi  ← PH14, GPIO activo
gpio-2047 (usb0-vbus) out lo ← AXP GPIO1, INACTIVO

usb0-vbus    1    0    0 unknown  5000mV  0mA  5000mV  5000mV
usb1-vbus    1    0    0 unknown  5000mV  0mA  5000mV  5000mV
```

Ambos reguladores muestran `0mA` de consumo real.

### DTS actual (`u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts`)
- `&ehci0` → status "okay" ✅
- `&ohci0` → status "okay" ✅
- `&usbphy1` → status "okay", `phy-supply = <&reg_usb1_vbus>` ✅
- `reg_usb0_vbus` → AXP GPIO1, always-on, active-high
- `reg_usb1_vbus` → PH14, always-on, active-high
- **NO hay referencia a `ehci1`/`ohci1`/`usbphy2`** — el A80 tiene 3 controladores USB (ehci0/1/2)

## Pruebas realizadas

1. **Reset del hub vía sysfs**: `echo 0/1 > /sys/bus/usb/devices/1-1/authorized` → hub se re-enumeró pero sin downstream
2. **Disable autosuspend**: `echo on > /sys/bus/usb/devices/1-1/power/control` → sin cambio
3. **Over-current counters**: todos en 0 → no hay protección de corriente activada
4. **PH14 (usb1-vbus)**: `out hi` ✅ → GPIO activo pero regulador muestra 0mA
5. **usb0-vbus**: `out lo` ❌ → regulador OTG no está entregando
6. **Módulos cargados**: `ehci_hcd`, `ohci_hcd`, `ehci_platform`, `ohci_platform`, `phy_sun9i_usb` ✅

## Resultado

✅ USB Type-A funcional con `phy-supply = <&reg_usb1_vbus>` en `usbphy1`.

Notas:
- U-Boot confirmó que el DTB nuevo se carga desde `mmc0:2` en `/boot/sun9i-a80-cubieboard4.dtb`.
- El primer intento de arranque con el DTB nuevo quedó detenido después de `Starting kernel ...`, pero tras power-cycle posteriores el sistema arrancó y enumeró el teclado. Vigilar si el arranque queda inestable.
- El binding moderno de A80 (`allwinner,sun9i-a80-usb-phy.yaml`) usa `phy-supply`, no `usb0_vbus-supply`/`usb1_vbus-supply`.

## Archivos clave
- DTS: `u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts`
- DTB compilado: `dtb/sun9i-a80-cubieboard4.dtb`
- FEX vendor referencia: `notes/2026-05-21-inspeccion-imagenes-vendor.md`
- Serial: `/dev/cu.usbserial-14230` @ 115200 8N1
- tmux session: `uart`

## Próximos pasos recomendados

1. Probar al menos otro dispositivo USB: pendrive, mouse y adaptador Ethernet/serial si hay.
2. Capturar `cat /sys/kernel/debug/usb/devices` con el teclado enumerado.
3. Si el arranque vuelve a colgar, comparar contra `/boot/sun9i-a80-cubieboard4.dtb.pre-phy-supply`.
4. Limpiar propiedades/reguladores USB que queden sin uso cuando el fix quede estable.

## Contexto adicional

- El hub `05e3:0608` es un hub Genesys Logic interno a la placa, no un dispositivo externo
- El vendor FEX define `usb1` como host con VBUS drive por PH14
- No hay `power_supply` classes del AXP expuestas en `/sys/class/power_supply/`
- El driver `phy_sun9i_usb` está cargado con 2 instancias
