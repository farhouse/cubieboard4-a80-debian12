# Handoff: CONFIG_MMC_BROKEN_CD build & eMMC boot test

Fecha: 2026-05-25

## Objetivo

Resolver el bloqueo de eMMC boot donde U-Boot proper reporta `MMC: no card present`
para todos los controladores MMC al bootear sin microSD.

## Hipotesis y fix aplicado

El error `MMC: no card present` sale de `mmc_start_init()` en
`drivers/mmc/mmc.c:3019`. La variable `no_card` se setea como `mmc_getcd(mmc) == 0`.

Fix: `CONFIG_MMC_BROKEN_CD=y` en `configs/Cubieboard4_defconfig`, que cambia el
preprocesador en `mmc.c:3007`:

```c
#if !defined(CONFIG_MMC_BROKEN_CD)
	no_card = mmc_getcd(mmc) == 0;
#else
	no_card = 0;
#endif
```

## Build

- Source: U-Boot 2025.07-rc4 en `/root/u-boot/` (eMMC Debian 12)
- Config: `Cubieboard4_defconfig` + `CONFIG_MMC_BROKEN_CD=y`
- Build nativo en Cubieboard4 (armhf, 8 cores, ~30 min)
- Problemas encontrados durante build:
  1. Missing `common/spl/Kconfig` → tarball incompleto, rebuild con source completo
  2. Missing `ctype.h` → include muerto en `cmd/setexpr.c`, eliminado
  3. Missing `dt-bindings/gpio/gpio.h` → extracción incompleta, re-extraer
  4. Missing `gnutls/gnutls.h` → `apt install libgnutls28-dev`
  5. Missing `python3` → `apt install python3 python3-pip`
  6. Binman no instalado → `pip install` + wrapper script en `tools/binman/binman`
  7. `_libfdt.so: ELFCLASS64` → conflicto x86_64/armhf, reemplazar con .so armhf
  8. Missing `swig` → `apt install swig`

- Binary final: `u-boot-sunxi-with-spl.bin` (506880 bytes, +2720 vs original 504160)

## Flashing

```sh
dd if=u-boot-sunxi-with-spl.bin of=/dev/mmcblk1boot0 bs=1024 conv=fsync
# noto: hubo que desbloquear con force_ro primero
495+0 records in, 495+0 records out, 506880 bytes, 7.5 MB/s
```

## boot.scr generado para eMMC

```sh
ROOT_UUID=19adddd1-13cf-46e4-8985-2d62c853be56
# boot.cmd con devnum 1, root=UUID=...
mkimage -A arm -O linux -T script -C none -d boot.cmd boot.scr
# copiado a mmcblk1p1 (FAT boot) y mmcblk1p2:/boot/ (ext4 rootfs)
```

## Test: eMMC boot sin SD

Resultado: **fix parcial**. U-Boot proper arranca desde eMMC, llega al shell,
pero `mmc rescan`/`mmc dev` falla con "MMC: no card present" para **todos**
los dispositivos (0=SD, 1=eMMC, 2=SDIO).

```
U-Boot 2025.07-rc4-dirty ...
MMC: no card present

Device 0: unknown device
...
=>

=> mmc list
mmc@1c0f000: 0
mmc@1c10000: 2
mmc@1c11000: 1

=> mmc dev 1 && mmc info
MMC: no card present
```

Los 3 controladores MMC aparecen en `mmc list` pero todos fallan al acceder.

### Análisis del código relevante

`cmd/mmc.c:__init_mmc_device()`:

```c
if (!mmc_getcd(mmc))
    force_init = true;
if (force_init)
    mmc->has_init = 0;
if (mmc_init(mmc))
    return NULL;
```

Llama a `mmc_getcd()` DIRECTAMENTE, sin pasar por `CONFIG_MMC_BROKEN_CD`.
`CONFIG_MMC_BROKEN_CD` solo afecta `mmc.c:mmc_start_init()`.

`drivers/mmc/sunxi_mmc.c:sunxi_mmc_getcd()`:

```c
if ((mmc->cfg->host_caps & MMC_CAP_NONREMOVABLE) ||
    (mmc->cfg->host_caps & MMC_CAP_NEEDS_POLL))
    return 1;
```

Debería retornar 1 para eMMC (non-removable en DTS). Pero retorna 0.

`mmc_of_parse()` en `mmc-uclass.c:281` parsea `non-removable` a
`MMC_CAP_NONREMOVABLE`. Llamado desde `sunxi_mmc_probe()`.

### Verificación post-test

- Binary en eMMC boot partition (`/dev/mmcblk2boot0`) contiene strings
  "U-Boot" y "broken-cd".
- Tamaño 506880 bytes confirma binary rebuilt.
- Source U-Boot eliminado del eMMC rootfs durante rebuild. Solo queda
  el binary en la boot partition.

## Próximos pasos sugeridos

1. **Verificar que CONFIG_MMC_BROKEN_CD esté realmente compilado**:
   - Extraer `u-boot` ELF del eMMC boot partition
   - Buscar la función `mmc_start_init` y confirmar que no tiene el check
     `mmc_getcd(mmc) == 0`

2. **Debug del driver sunxi_mmc_getcd()**:
   - Averiguar por qué retorna 0 pese a `non-removable` en DTS
   - Posible causa: `mmc_of_parse()` no se ejecuta antes de `get_cd`
   - O: `host_caps` se pierden/resetean entre probe y get_cd

3. **Parseo DTS de U-Boot vs kernel**:
   - U-Boot proper usa su propio DTB embebido en `u-boot.bin`
   - Comparar `arch/arm/dts/sun9i-a80-cubieboard4.dts` de U-Boot contra
     el DTB final validado en `dtb/sun9i-a80-cubieboard4.dtb`
   - El DTS de U-Boot puede diferir del kernel (ej. mmc2 sin `mmc-hs200-1.8v`)
   - Diferencia clave: el DTS de kernel en `dtb/` fue modificado con fix
     para USB y MMC; el DTS de U-Boot es el original de mainline

4. **Alternativa: fix en __init_mmc_device()**:
   - Agregar bypass similar a CONFIG_MMC_BROKEN_CD en `cmd/mmc.c`
   - O modificar `sunxi_mmc_getcd()` para no checkear cd en absoluto

5. **Alternativa: flashear solo el SPL desde nuevo build**:
   - Si el SPL del nuevo build funciona pero U-Boot proper no, se podría
     mantener SPL nuevo y usar U-Boot proper del build anterior
   - Pero el build anterior también falla con "MMC: no card present"

6. **Probar con el DTB del kernel**:
   - Hacer que U-Boot proper cargue el DTB desde `/boot/` en lugar del
     DTB embebido
   - El DTB del kernel (`dtb/sun9i-a80-cubieboard4.dtb`) tiene configuración
     validada de MMC que funciona

## Recursos

- Binary flasheado: `/dev/mmcblk2boot0` (eMMC, cuando bootea desde SD)
- Dump binario: `/tmp/emmc-uboot-check.bin` en SD Debian
- Source U-Boot: ya NO disponible en eMMC (eliminado). Reconstruir desde
  macOS: `u-boot/` en el workspace.
- Config change: `configs/Cubieboard4_defconfig` en workspace.
- Archivos DTS U-Boot: `arch/arm/dts/sun9i-a80-cubieboard4.dts` en workspace.
- DTS kernel validado: `dtb/sun9i-a80-cubieboard4.dtb` en workspace.
