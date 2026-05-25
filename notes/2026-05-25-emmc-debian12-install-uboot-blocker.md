# Instalacion Debian 12 a eMMC y blocker U-Boot

Fecha: 2026-05-25

## Objetivo

Copiar el sistema Debian 12 funcional desde microSD a la eMMC interna y validar
boot sin microSD.

## Resultado

- La copia de Debian 12 a eMMC se completo correctamente.
- El backup preventivo de eMMC se guardo en un pendrive USB montado en
  `/mnt/usb/cb4-emmc-backup`.
- La particion root eMMC se reformateo como ext4 con label `cb4-rootfs`.
- El nuevo UUID de `/dev/mmcblk1p2` fue:

```text
19adddd1-13cf-46e4-8985-2d62c853be56
```

- El instalador genero `/boot/boot.cmd` y `/boot/boot.scr` dentro del rootfs de
  eMMC.
- El sistema no booteo Debian 12 desde eMMC sin microSD.

## Comando ejecutado

```sh
/root/install-to-emmc.sh --execute --backup-dir /mnt/usb/cb4-emmc-backup
```

El primer intento quedo bloqueado en `mkfs.ext4` durante discard:

```text
Discarding device blocks:      0/919296
```

Se interrumpio antes de montar/copiar, se ajusto el script para usar
`mkfs.ext4 -E nodiscard`, y se repitio la instalacion:

```text
+ mkfs.ext4 -F -E nodiscard -L cb4-rootfs /dev/mmcblk1p2
Creating filesystem with 919296 4k blocks and 230144 inodes
Writing superblocks and filesystem accounting information: done
```

La copia y generacion de boot script finalizaron:

```text
Copying running SD rootfs to eMMC...
+ rsync -aHAX --numeric-ids ...

Writing eMMC boot script...
Image Type:   ARM Linux Script (uncompressed)
Data Size:    471 Bytes

Final verification...
EXT4-fs (mmcblk1p2): unmounting filesystem.

Done.
```

## Estado final desde Linux antes de apagar

```text
mmcblk1
├─mmcblk1p1  28M  vfat
└─mmcblk1p2  3.5G ext4  cb4-rootfs  19adddd1-13cf-46e4-8985-2d62c853be56
```

Backups creados en USB:

```text
cb4-emmc-20260525-000407-first-32m.bin
cb4-emmc-20260525-000407-first-32m.sha256
cb4-emmc-20260525-000407-layout.txt
cb4-emmc-20260525-000632-first-32m.bin
cb4-emmc-20260525-000632-first-32m.sha256
cb4-emmc-20260525-000632-layout.txt
```

## Fallo de boot sin microSD

El SPL si cargo U-Boot desde eMMC:

```text
U-Boot SPL 2025.07-rc4-dirty (Jun 13 2025 - 12:27:12 -0300)
DRAM: 2048 MiB
Trying to boot from MMC2
```

Pero U-Boot proper no pudo acceder a los MMC:

```text
U-Boot 2025.07-rc4-dirty (Jun 13 2025 - 12:27:12 -0300) Allwinner Technology
MMC:   mmc@1c0f000: 0, mmc@1c10000: 2, mmc@1c11000: 1
Loading Environment from FAT... ** Bad device specification mmc 1 **
...
MMC: no card present
Device 0: unknown device
Config file not found
```

Pruebas manuales en prompt U-Boot:

```text
=> mmc list
mmc@1c0f000: 0
mmc@1c10000: 2
mmc@1c11000: 1

=> mmc dev 2
=> mmc rescan
MMC: no card present

=> mmc dev 1
=> mmc rescan
MMC: no card present

=> mmc dev 0
MMC: no card present
```

## Conclusion

El blocker actual no es el rootfs Debian 12 ni el contenido de `/boot` en
eMMC. El SPL puede leer eMMC suficiente para cargar U-Boot, pero U-Boot proper
no detecta ningun MMC utilizable cuando se arranca sin microSD.

Esto deja un pendiente de implementacion en U-Boot/DTB/env:

- revisar por que U-Boot proper marca `MMC: no card present` para `mmc2`;
- validar si el DTS de U-Boot para eMMC necesita `broken-cd`, `non-removable`,
  reset o pinctrl/reguladores distintos;
- corregir tambien el boot script/env para usar el `devnum` real de eMMC una
  vez que U-Boot proper pueda leerla;
- mantener `mkfs.ext4 -E nodiscard` en el instalador para evitar bloqueo en
  eMMC durante formateo.

