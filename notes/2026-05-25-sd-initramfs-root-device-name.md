# SD boot cae a initramfs por nombre mmcblk inestable

Fecha: 2026-05-25

## Contexto

Despues de instalar Debian 12 en eMMC, el boot desde microSD llego a
initramfs. La eMMC sin microSD sigue bloqueada antes de kernel: SPL carga
U-Boot desde `MMC2`, pero U-Boot proper no detecta MMC/eMMC utilizable.

## Observacion UART

El boot desde microSD carga U-Boot y encuentra `/boot/boot.scr`:

```text
Trying to boot from MMC1
MMC:   mmc@1c0f000: 0, mmc@1c10000: 2, mmc@1c11000: 1
Scanning mmc 0:2...
Found U-Boot script /boot/boot.scr
```

El kernel recibe:

```text
Kernel command line: root=/dev/mmcblk0p2 rw rootwait
```

Pero Linux enumera los dispositivos asi en ese arranque:

```text
mmcblk1: mmc1:0007 SD8GB 7.42 GiB
 mmcblk1: p1 p2
mmcblk2: mmc2:0001 NCard  7.30 GiB
 mmcblk2: p1 p2
mmcblk2boot0: mmc2:0001 NCard  4.00 MiB
mmcblk2boot1: mmc2:0001 NCard  4.00 MiB
mmc0: new high speed SDIO card at address 0001
```

Resultado: el rootfs real de la SD no esta en `/dev/mmcblk0p2`, sino en
`/dev/mmcblk1p2`. El kernel cae a initramfs porque espera un nombre de bloque
fragil.

## Conclusion

El root por `/dev/mmcblkNp2` no es estable en esta placa. La presencia de SD,
eMMC y SDIO WiFi puede cambiar el orden de enumeracion de Linux.

Tampoco conviene volver a `root=PARTUUID=...` mientras SD y eMMC puedan
compartir `PARTUUID` por provenir del mismo layout.

La opcion correcta para los scripts de boot es usar el UUID del filesystem:

```text
root=UUID=<uuid-del-rootfs>
```

## Cambios aplicados

- `scripts/build-sd-image.sh` ahora regenera `/boot/boot.cmd` y
  `/boot/boot.scr` con `root=UUID=...` para la particion rootfs de la imagen.
- `scripts/install-to-emmc.sh` tambien genera `boot.scr` con `root=UUID=...`
  para la particion eMMC destino.
- README actualizado: ya no afirma que la SD siempre aparece como `mmcblk0`.

## Pendiente de validacion

Reconstruir una microSD con `scripts/build-sd-image.sh` en Linux y validar que
el kernel bootea usando `root=UUID=...` aunque la SD aparezca como `mmcblk1`.
