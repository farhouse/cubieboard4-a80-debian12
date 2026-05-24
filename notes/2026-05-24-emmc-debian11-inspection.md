# Inspeccion eMMC Debian 11

Fecha: 2026-05-24

## Objetivo

Verificar el estado real de la eMMC interna sin modificarla, arrancando desde la
microSD Debian 12 validada.

## Resultado corto

- La placa arranco desde microSD: root actual `/dev/mmcblk0p2`.
- La eMMC aparece como `/dev/mmcblk1`, 7.3 GiB.
- La eMMC contiene Debian 11 Bullseye con kernel `5.10.0-34-armmp`.
- La particion FAT de eMMC esta intencionalmente vacia.
- El boot de Debian 11 esta en `/boot` dentro de `mmcblk1p2`.
- El `boot.cmd` de eMMC esta preparado para `devnum 1`, o sea para cargar desde
  eMMC.
- SD y eMMC tienen el mismo `PARTUUID` para p1/p2; esto es un riesgo si se usa
  `root=PARTUUID=...` con ambos medios insertados.

No se valido bootear Debian 12 desde eMMC.

## Sistema activo

```text
Linux debian 6.1.0-37-armmp #1 SMP Debian 6.1.140-1 (2025-05-22) armv7l GNU/Linux
root=/dev/mmcblk0p2 rw rootwait
/ -> /dev/mmcblk0p2 ext4
```

## Layout detectado

```text
mmcblk0      7.4G disk
├─mmcblk0p1   28M vfat  UUID=BAC3-19DE PARTUUID=800e6fd4-01
└─mmcblk0p2  3.5G ext4  UUID=66c76c3a-4c75-4bb3-9665-dbb0dce7649e PARTUUID=800e6fd4-02 /

mmcblk1      7.3G disk
├─mmcblk1p1   28M vfat  UUID=BAC3-19DE PARTUUID=800e6fd4-01
└─mmcblk1p2  3.5G ext4  UUID=f825ef93-8094-4018-9835-a18536723e8c PARTUUID=800e6fd4-02

mmcblk1boot0 4M
mmcblk1boot1 4M
```

Particiones:

```text
/sys/block/mmcblk0/mmcblk0p1 start=8192 size=57344
/sys/block/mmcblk0/mmcblk0p2 start=65536 size=7354368
/sys/block/mmcblk1/mmcblk1p1 start=8192 size=57344
/sys/block/mmcblk1/mmcblk1p2 start=65536 size=7354368
```

## Contenido eMMC

`/dev/mmcblk1p1`:

```text
/PARTITION_INTENTIONALLY_EMPTY.TXT
```

`/dev/mmcblk1p2/etc/os-release`:

```text
PRETTY_NAME="Debian GNU/Linux 11 (bullseye)"
VERSION_ID="11"
VERSION="11 (bullseye)"
VERSION_CODENAME=bullseye
```

`/dev/mmcblk1p2/boot`:

```text
/boot/System.map-5.10.0-34-armmp
/boot/boot.cmd
/boot/boot.scr
/boot/config-5.10.0-34-armmp
/boot/initrd.img-5.10.0-34-armmp
/boot/vmlinuz-5.10.0-34-armmp
```

`/dev/mmcblk1p2/etc/fstab`:

```text
tmpfs /tmp tmpfs nodev,nosuid 0 0
```

## Boot script eMMC

`/boot/boot.cmd`:

```text
setenv devtype mmc
setenv devnum 1
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/vmlinuz-5.10.0-34-armmp
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /boot/initrd.img-5.10.0-34-armmp
setenv ramdisk_size ${filesize}
part uuid ${devtype} ${devnum}:${distro_bootpart} partuuid
setenv bootargs root=PARTUUID=${partuuid} rw rootwait
for fdtpath in /lib/firmware/5.10.0-34-armmp/device-tree/${vendor} /lib/firmware/5.10.0-34-armmp/device-tree /usr/lib/linux-image-5.10.0-34-armmp/${vendor} /usr/lib/linux-image-5.10.0-34-armmp /usr/lib/linux/${vendor} /usr/lib/linux; do
  if test -e ${devtype} ${devnum}:${distro_bootpart} ${fdtpath}/${fdtfile}; then
    load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${fdtpath}/${fdtfile}
    bootz ${kernel_addr_r} ${ramdisk_addr_r}:${ramdisk_size} ${fdt_addr_r}
  fi
done
bootz ${kernel_addr_r} ${ramdisk_addr_r}:${ramdisk_size} ${fdtcontroladdr}
```

## Hashes de zona raw inicial

Lectura no destructiva:

```text
sha256(first 32 MiB mmcblk0) = 859b08799075c58b7717e974d178e042f4c3c1668a47402e44ef0577fe9dc4ae
sha256(first 32 MiB mmcblk1) = bc9848f22936f682c906a8fa329a217dfe8d587f6c25060b667a177004bea041

sha256(first 1 MiB mmcblk0) = 5bae86250482f31057b5907843590fca1b71bbce40e3152beb9c1c6dd06b65c6
sha256(first 1 MiB mmcblk1) = 268af79067a457edf42fd4d33951466d457a21aa4a673c329dea6496e1303890
```

Las regiones raw iniciales no son identicas entre SD y eMMC.

## Implicancias

- La eMMC no esta vacia; conviene preservarla antes de cualquier instalador.
- Un script `install-to-emmc.sh` no debe usar `root=PARTUUID=800e6fd4-02` si SD
  y eMMC conviven con PARTUUID duplicados.
- Para instalar Debian 12 a eMMC, primero conviene capturar backup de
  `/dev/mmcblk1` completo o al menos de las regiones raw iniciales y particiones.
- Luego se puede evaluar si basta con adaptar el rootfs/boot.cmd de Johan para
  `devnum 1`, o si hay que reinstalar bootloader raw en eMMC.
