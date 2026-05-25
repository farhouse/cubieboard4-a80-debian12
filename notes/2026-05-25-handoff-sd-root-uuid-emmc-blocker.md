# Handoff: SD root UUID fix y blocker eMMC

Fecha: 2026-05-25

## Estado actual

La microSD existente vuelve a bootear sola a Debian 12. El problema era que
`/boot/boot.scr` usaba:

```text
root=/dev/mmcblk0p2
```

Ese nombre no es estable en Cubieboard4 A80 cuando conviven SD, eMMC y SDIO
WiFi. En diferentes arranques la SD aparecio como `mmcblk0` y tambien como
`mmcblk1`. La solucion aplicada fue usar el UUID del filesystem root:

```text
root=UUID=66c76c3a-4c75-4bb3-9665-dbb0dce7649e
```

Validacion final: luego de regenerar `/boot/boot.scr` en la SD y reiniciar sin
intervenir U-Boot, el sistema llego a:

```text
Debian GNU/Linux 12 debian ttyS0
debian login:
```

## Cambios ya subidos al repo

Commits relevantes:

```text
c02c778 docs: record sd root uuid boot fix
f5868b1 tools: use root uuid in boot scripts
c7fc902 docs: translate readme to english
62ce9fb tools: add reproducible sd image builder
5a15460 docs: record emmc boot blocker and release assets
```

Cambios de tooling:

- `scripts/build-sd-image.sh` genera imagen SD desde assets preservados en la
  GitHub Release `external-images-2026-05`.
- El builder instala DTB, firmware AP6330 y ahora regenera `/boot/boot.scr`
  con `root=UUID=...`.
- `scripts/install-to-emmc.sh` tambien genera boot scripts con
  `root=UUID=...`.
- El instalador eMMC usa `mkfs.ext4 -E nodiscard` para evitar bloqueo durante
  discard.

Cambios de docs:

- README principal esta en ingles.
- `docs/boot/matriz-pruebas-arranque.md` refleja el fallo de root por
  `mmcblkN` y la validacion OK posterior.
- `docs/estado-validado.md` ya no asume que SD siempre es `mmcblk0`.
- `notes/2026-05-25-sd-initramfs-root-device-name.md` contiene el detalle del
  incidente y fix.
- `notes/2026-05-25-emmc-debian12-install-uboot-blocker.md` contiene el estado
  de eMMC.

## Estado de la SD real

Archivos modificados dentro de la SD:

```text
/boot/boot.cmd
/boot/boot.scr
```

Backups dejados en la SD:

```text
/boot/boot.cmd.pre-root-uuid-fix
/boot/boot.scr.pre-root-uuid-fix
```

Contenido esencial del nuevo `/boot/boot.cmd`:

```text
setenv devtype mmc
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/vmlinuz-6.1.0-37-armmp
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /boot/initrd.img-6.1.0-37-armmp
setenv ramdisk_size ${filesize}
setenv bootargs root=UUID=66c76c3a-4c75-4bb3-9665-dbb0dce7649e rw rootwait
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /boot/sun9i-a80-cubieboard4.dtb
bootz ${kernel_addr_r} ${ramdisk_addr_r}:${ramdisk_size} ${fdt_addr_r}
```

Comando usado para compilar:

```sh
mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
sync
```

## Estado de eMMC

La instalacion Debian 12 a eMMC se completo, pero el boot sin microSD sigue
bloqueado antes del kernel.

Datos relevantes:

```text
eMMC root UUID: 19adddd1-13cf-46e4-8985-2d62c853be56
eMMC root label: cb4-rootfs
```

El SPL carga U-Boot desde eMMC:

```text
Trying to boot from MMC2
```

Pero U-Boot proper no puede acceder a MMC/eMMC:

```text
MMC: no card present
```

Conclusión actual: el blocker eMMC no es el rootfs Debian 12 ni el
`boot.scr`; es inicializacion MMC/eMMC en U-Boot proper al arrancar sin SD.

## Siguiente paso recomendado

Opcion A, reproducibilidad:

1. Correr `scripts/build-sd-image.sh` en una maquina Linux o VM Linux.
2. Confirmar que la imagen generada contiene `/boot/boot.scr` con
   `root=UUID=...`.
3. Grabarla a una SD limpia y validar boot automatico.

Opcion B, eMMC boot:

1. Investigar U-Boot proper con foco en `mmc@1c11000` / `mmc2`.
2. Revisar DTS de U-Boot para eMMC: `non-removable`, `broken-cd`,
   `cap-mmc-hw-reset`, pinctrl, reguladores y reset.
3. Comparar contra vendor/FEX y contra el estado donde Linux detecta eMMC.
4. Una vez que U-Boot proper lea eMMC, ajustar `devnum`/boot flow para cargar
   `/boot/boot.scr` desde eMMC.

Recomendacion practica: cerrar primero la reproducibilidad de SD con el builder
en Linux. Despues retomar eMMC, porque eMMC requiere tocar U-Boot/DTB y es un
problema distinto al rootfs.
