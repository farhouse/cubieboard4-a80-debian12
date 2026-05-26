# Estado validado - Cubieboard4 A80 revive

Fecha de consolidacion: 2026-05-26

Este documento resume el estado estable del revive de la Cubieboard4 A80. Las
notas en `notes/` quedan como bitacora de investigacion; este archivo debe
usarse como referencia rapida de lo que ya funciono, que cambios lo hicieron
posible y que queda pendiente.

## Resumen ejecutivo

La placa bootea Debian 12 Bookworm desde microSD o eMMC con U-Boot 2025.07-rc4
y DTB corregido. Quedaron validados:

| Subsistema | Estado | Resultado validado |
|---|---|---|
| Boot desde microSD | Funciona | Arranque automatico via `boot.scr`, con `broken-cd` en `mmc0` |
| Rootfs Bookworm | Funciona | Kernel `6.1.0-37-armmp`, login/shell usable |
| Ethernet RTL8211E | Funciona | Link Gigabit Full Duplex |
| USB Type-A | Funciona | Hub interno `05e3:0608`, pendrive probado en los 4 puertos |
| WiFi AP6330 | Funciona | `wlan0` levanta y escanea redes; BCM4330/4, HT hasta 300 Mbps |
| eMMC | Funciona | Boot sin microSD: SPL → U-Boot proper → kernel → Debian 12 login. Root cause: typo `CONFIG_MACH_SUN9I_A80` → `CONFIG_MACH_SUN9I` en `get_mclk_offset()` (`drivers/mmc/sunxi_mmc.c:649`) |
| Bluetooth AP6330 | Pendiente | Firmware `bcm40183b2.hcd` localizado, falta configurar |
| HDMI/VGA | Pendiente | No probado todavia |

## Baseline de sistema

- Placa: Cubieboard4 / CC-A80, Allwinner A80, 2 GiB RAM.
- Bootloader: `U-Boot 2025.07-rc4` (fix clock register apply).
- Sistema: Debian 12 Bookworm armhf.
- Kernel: `6.1.0-48-armmp` (eMMC boot), `6.1.0-37-armmp` (SD boot).
- Medio principal: microSD o eMMC.
- DTB usado: `dtb/sun9i-a80-cubieboard4.dtb`, persistido en `/boot/sun9i-a80-cubieboard4.dtb`.
- Serial: `/dev/cu.usbserial-14230`, `115200 8N1`, sin flow control.

Comando serial que funciono:

```sh
picocom -b 115200 --databits 8 --parity n --stopbits 1 --flow n /dev/cu.usbserial-14230
```

## Imagen Bookworm usada

La imagen de prueba se armo combinando:

- `images/boot-cubieboard4.bin.gz`
- `images/debian-bookworm-armhf-vim3ve.bin.gz`

Flujo usado:

```sh
cp /private/tmp/cb4-bookworm/boot-cubieboard4.bin \
  /private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img

dd if=/private/tmp/cb4-bookworm/debian-bookworm-armhf-vim3ve.bin \
  of=/private/tmp/cb4-bookworm/cubieboard4-bookworm-test.img \
  bs=1m seek=32 conv=notrunc status=progress
```

Particiones verificadas:

- Particion 1: FAT32 boot, sector `8192`, 28 MiB.
- Particion 2: ext4 rootfs, sector `65536`, aproximadamente 3.5 GiB.

Para grabar en macOS, verificar primero el dispositivo con
`diskutil list external physical`:

```sh
diskutil unmountDisk force /dev/disk4

sudo dd if=/private/tmp/cb4-bookworm/cubieboard4-bookworm-test-nocd.img \
  of=/dev/rdisk4 bs=4m conv=sync status=progress

sync
diskutil eject /dev/disk4
```

## Cambios DTS que quedaron validados

Archivo fuente trabajado:

```text
u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts
```

DTB compilado y usado:

```text
dtb/sun9i-a80-cubieboard4.dtb
```

### microSD en `mmc0`

El problema inicial era el card-detect de `mmc0`. SPL podia arrancar desde la
SD, pero U-Boot proper reportaba `MMC: no card present`.

El nodo original dependia de `PH18`:

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

La solucion estable fue ignorar card-detect:

```dts
&mmc0 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc0_pins>;
	vmmc-supply = <&reg_dcdc1>;
	bus-width = <4>;
	broken-cd;
	status = "okay";
};
```

Resultado validado:

- U-Boot lee `mmc 0`.
- Boot automatico desde `boot.scr` en `mmc 0:2`.
- Linux puede enumerar SD/eMMC con distintos nombres `mmcblkN` segun el orden
  de probe, especialmente con SDIO WiFi presente. No usar `/dev/mmcblkNp2`
  como root persistente; usar `root=UUID=...`.

### WiFi AP6330 en `mmc1`

La inspeccion de imagenes vendor y Linaro mostro que el WiFi es AP6330/Broadcom
en `mmc1`, SDIO 4-bit, pines `PG0-PG5`. El DTS base tenia `mmc1` con rasgos de
eMMC, lo que bloqueaba el WiFi.

Configuracion validada:

```dts
&mmc1 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc1_pins>;
	vmmc-supply = <&reg_dldo1>;
	vqmmc-supply = <&reg_cldo3>;
	mmc-pwrseq = <&wifi_pwrseq>;
	bus-width = <4>;
	non-removable;
	broken-cd;
	disable-wp;
	no-mmc;
	cap-sd-highspeed;
	no-1-8-v;
	status = "okay";
};

&mmc1_pins {
	pins = "PG0", "PG1", "PG2", "PG3", "PG4", "PG5";
	function = "mmc1";
	drive-strength = <0x14>;
	bias-pull-up;
};
```

Secuencia de power validada:

```dts
wifi_pwrseq: wifi-pwrseq {
	compatible = "mmc-pwrseq-simple";
	clocks = <&ac100_rtc 1>;
	clock-names = "ext_clock";
	reset-gpios = <&r_pio 0 2 GPIO_ACTIVE_LOW>; /* PL2 WL-PMU-EN */
	post-power-on-delay-ms = <50>;
};
```

Regulador adicional validado:

```dts
reg_ldoio0: ldoio0 {
	compatible = "regulator-fixed";
	regulator-name = "vcc-wifi-ldoio0";
	regulator-min-microvolt = <3300000>;
	regulator-max-microvolt = <3300000>;
	gpio = <&axp_gpio 0 GPIO_ACTIVE_HIGH>;
	enable-active-high;
	regulator-always-on;
};
```

Errores resueltos:

```text
sunxi-mmc 1c10000.mmc: fatal err update clk timeout
brcmfmac_sdio_htclk: HT Avail timeout
```

### eMMC en `mmc2`

Segun el FEX vendor, la eMMC corresponde a `mmc2`, 8-bit, pines `PC6-PC16`.
Queda como almacenamiento interno detectado por Linux.

#### Instalacion Debian 12

La eMMC tenia Debian 11 Bullseye (`mmcblk1p2`) con kernel `5.10.0-34-armmp`.
El 2026-05-25 se ejecuto el instalador `scripts/install-to-emmc.sh` y se copio
Debian 12 desde la microSD a `/dev/mmcblk1p2`. El rootfs eMMC quedo como ext4
con label `cb4-rootfs` y UUID:

```text
19adddd1-13cf-46e4-8985-2d62c853be56
```

La instalacion a eMMC completo correctamente, incluyendo backup previo en USB,
`rsync`, generacion de `boot.cmd`/`boot.scr`, `sync` y `umount`.

#### Boot sin SD: root cause y fix

El 2026-05-26 se resolvio el boot desde eMMC sin microSD. El SPL cargaba
U-Boot desde MMC2 correctamente, pero U-Boot proper fallaba con
`MMC: no card present`.

**Root cause**: `get_mclk_offset()` en `drivers/mmc/sunxi_mmc.c:649`
chequeaba `CONFIG_MACH_SUN9I_A80` (no existe en Kconfig) en vez de
`CONFIG_MACH_SUN9I`. Esto causaba que U-Boot proper (DM path) escribiera
el MMC2 clock register en `0x06000090` (default) en lugar de `0x06000418`,
corrompiendo la respuesta de CMD2 (ALL_CID).

```c
// ANTES (bug)
if (IS_ENABLED(CONFIG_MACH_SUN9I_A80))  // no existe!
    return 0x410;
return 0x88;  // direccion incorrecta → CMD2 falla

// DESPUES (fix)
if (IS_ENABLED(CONFIG_MACH_SUN9I))
    return 0x410;
```

**Fix adicional**: se agrego `CONFIG_MACH_SUN9I` a la condicion de 8-bit mode
en `sunxi_mmc_init()` para SPL.

**Fix DTS**: se agregaron `mmc-hs200-1.8v`, `broken-cd`, `disable-wp`, `no-sd`
al nodo mmc2.

#### Resultado validado

```
U-Boot SPL 2025.07-rc4 (May 26 2026 - 15:33:13 +0000)
U-Boot 2025.07-rc4 (May 26 2026 - 15:33:13 +0000)
DRAM:  2 GiB
MMC:   mmc 0 set mod-clk req 24000000 parent 24000000 n 1 m 1 rate 24000000
Found U-Boot script /boot/boot.scr
Loading Ramdisk ...
mmc2: new DDR MMC card at address 0001
mmcblk2: mmc2:0001 NCard  7.30 GiB
Debian GNU/Linux 12 debian ttyS0
```

Referencia: `notes/2026-05-26-emmc-boot-fix-clock-register.md`.

#### Riesgos

- SD y eMMC comparten los mismos `PARTUUID` (`800e6fd4-01` y `800e6fd4-02`).
  Evitar `root=PARTUUID=...` mientras ambos medios esten presentes, salvo que
  antes se regeneren identificadores.
- El boot desde SD puede caer a initramfs si `boot.scr` usa
  `root=/dev/mmcblk0p2`, porque Linux enumera SD como `mmcblk1` o `mmcblk0`
  segun orden de probe. Usar `root=UUID=...`.

#### Configuracion DTS final

```dts
&mmc2 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_dcdc1>;
	bus-width = <8>;
	non-removable;
	mmc-hs200-1.8v;
	broken-cd;
	disable-wp;
	no-sd;
	cap-mmc-hw-reset;
	status = "okay";
};
```

### USB Type-A

El hub interno `05e3:0608` enumeraba, pero no aparecian dispositivos downstream
hasta asociar los supplies correctos al PHY.

Fix validado para el primer bloque Type-A:

```dts
&ehci0 {
	status = "okay";
};

&ohci0 {
	status = "okay";
};

&usbphy1 {
	phy-supply = <&reg_usb1_vbus>;
	status = "okay";
};
```

Fix validado para el segundo bloque Type-A:

```dts
&ehci2 {
	status = "okay";
};

&ohci2 {
	status = "okay";
};

&usbphy3 {
	phy-supply = <&reg_usb2_vbus>;
	status = "okay";
};
```

Reguladores VBUS:

```dts
reg_usb0_vbus: usb0-vbus {
	compatible = "regulator-fixed";
	regulator-name = "usb0-vbus";
	regulator-min-microvolt = <5000000>;
	regulator-max-microvolt = <5000000>;
	gpio = <&axp_gpio 1 GPIO_ACTIVE_HIGH>;
	enable-active-high;
	regulator-always-on;
};

reg_usb1_vbus: usb1-vbus {
	compatible = "regulator-fixed";
	regulator-name = "usb1-vbus";
	regulator-min-microvolt = <5000000>;
	regulator-max-microvolt = <5000000>;
	gpio = <&pio 7 14 GPIO_ACTIVE_HIGH>; /* PH14 */
	enable-active-high;
	regulator-always-on;
};

reg_usb2_vbus: usb2-vbus {
	compatible = "regulator-fixed";
	regulator-name = "usb2-vbus";
	regulator-min-microvolt = <5000000>;
	regulator-max-microvolt = <5000000>;
	gpio = <&pio 7 15 GPIO_ACTIVE_HIGH>; /* PH15 */
	enable-active-high;
	regulator-always-on;
};
```

Resultado validado:

- Hub interno Genesys Logic `05e3:0608`.
- Teclado Logitech enumero como HID durante pruebas intermedias.
- Pendrive PHILIPS 62GB probado en los 4 puertos Type-A.

## Firmware AP6330

Los firmwares se extrajeron de las imagenes vendor/Linaro. Archivos relevantes
originales:

```text
lib/firmware/ap6330/fw_bcm40183b2_ag.bin
lib/firmware/ap6330/fw_bcm40183b2_ag_p2p.bin
lib/firmware/ap6330/fw_bcm40183b2_ag_apsta.bin
lib/firmware/ap6330/nvram_ap6330.txt
lib/firmware/ap6330/bcm40183b2.hcd
```

Instalacion validada para Linux mainline:

```text
/lib/firmware/brcm/brcmfmac4330-sdio.bin
/lib/firmware/brcm/brcmfmac4330-sdio.txt
```

Mapeo usado:

- `brcmfmac4330-sdio.bin`: desde `fw_bcm40183b2_ag.bin`, 239507 bytes.
- `brcmfmac4330-sdio.txt`: desde `nvram_ap6330.txt`.

Mensajes esperados:

```text
brcmfmac: brcm_fw_alloc_request: using brcm/brcmfmac4330-sdio for chip BCM4330/4
brcmfmac: Firmware: BCM4330/4 wl0: Jan  6 2014 15:11:29 version 5.90.195.89
wlan0: ether e0:76:d0:b0:d1:ea
```

Validacion final:

```sh
ifconfig wlan0 up
iw dev wlan0 scan
```

Resultado: `wlan0` escanea redes y reporta HT hasta 300 Mbps. Evidencia:
`logs/2026-05-22-final-wifi-validation.log`.

## Comandos de verificacion

Boot y almacenamiento:

```sh
cat /proc/partitions
findmnt /
```

USB:

```sh
lsusb
cat /sys/kernel/debug/usb/devices
```

WiFi:

```sh
ifconfig wlan0 up
iw dev wlan0 scan
```

Ethernet:

```sh
dmesg | grep -i 'Link is Up'
```

Serial host:

```sh
picocom -b 115200 --databits 8 --parity n --stopbits 1 --flow n /dev/cu.usbserial-14230
```

## Evidencia y documentos relacionados

- `docs/boot/matriz-pruebas-arranque.md`: matriz cronologica de pruebas.
- `logs/2026-05-22-final-wifi-validation.log`: evidencia limpia final de WiFi y Ethernet.
- `logs/serial-live.log`: log historico de bring-up; contiene errores previos y salida ruidosa.
- `notes/2026-05-22-handoff-final.md`: handoff final de la sesion.
- `notes/2026-05-22-wifi-ap6330.md`: resolucion especifica del WiFi.
- `notes/2026-05-21-handoff-usb-4puertos.md`: validacion USB 4 puertos.
- `notes/2026-05-21-inspeccion-imagenes-vendor.md`: referencia FEX/vendor para MMC, USB y AP6330.
- `notes/2026-05-24-emmc-debian11-inspection.md`: inspeccion read-only de la eMMC Debian 11 y riesgos para migracion.
- `notes/2026-05-25-emmc-debian12-install-uboot-blocker.md`: instalacion Debian 12 a eMMC y blocker U-Boot proper.
- `notes/2026-05-26-emmc-boot-fix-clock-register.md`: root cause y fix del clock register bug.
- `patches/2026-05-26-emmc-clock-register-fix.patch`: patch del fix.
- `patches/2026-05-26-emmc-dts-mmc2-properties.patch`: patch DTS mmc2.

## Pendientes

1. Bluetooth AP6330: instalar/configurar `bcm40183b2.hcd` y validar UART/GPIOs BT.
2. Conectividad WiFi completa: instalar `wpasupplicant` o `iwd` y probar asociacion a red.
3. HDMI/VGA: probar salida de video.
4. Capturar un boot log limpio completo con el DTB final, sin payloads de transferencia.
5. Promover o guardar referencias FEX en `docs/device-tree/` como tabla FEX -> DTS.
6. Reconstruir DTS source correspondiente al DTB final.
7. Enviar patch upstream: typo `CONFIG_MACH_SUN9I_A80` en `drivers/mmc/sunxi_mmc.c` afecta todos los sun9i-A80.

## Estado de commits

Commits relevantes ya presentes:

```text
fd6b4e7 docs(boot): add boot test matrix template
f0989bf feat(usb): enable all 4 Type-A ports and fix SD boot with broken-cd
abd0c25 feat(wifi): enable AP6330 SDIO WiFi with vendor firmware
db209b6 docs(handoff): add final session summary with USB + WiFi status
```
