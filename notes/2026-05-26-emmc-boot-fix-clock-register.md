# eMMC Boot Fix: U-Boot Proper MMC2 Clock Register Address Bug

## Summary

Root cause de que eMMC boot sin SD fallaba: U-Boot proper (DM path) escribía el
MMC2 clock register en dirección incorrecta (0x06000090 en vez de 0x06000418),
porque `get_mclk_offset()` chequeaba `CONFIG_MACH_SUN9I_A80` (no existe) en
vez de `CONFIG_MACH_SUN9I`. Esto corrompía la respuesta de CMD2 (ALL_CID) y
fallaba toda la inicialización MMC.

## Symptom

```
MMC: no card present
```

SPL cargaba U-Boot proper desde MMC2 correctamente (usaba ruta non-DM con
`CCU_MMC2_CLK_CFG=0x418` directo), pero al llegar a U-Boot proper, el DM MMC
init escribía clock config en `0x06000090` y luego CMD2 recibía `0xffffffff`
(CRC error / sin respuesta).

## Root Cause

### `drivers/mmc/sunxi_mmc.c:649`

```c
static unsigned get_mclk_offset(void)
{
    if (IS_ENABLED(CONFIG_MACH_SUN9I_A80))  // BUG: no existe
        return 0x410;
    ...
    return 0x88;  // default = direccion incorrecta para sun9i
}
```

`CONFIG_MACH_SUN9I_A80` **no está definido en ningún lado**. Los boards sun9i
usan `CONFIG_MACH_SUN9I`. Entonces `get_mclk_offset()` retorna `0x88` (default)
en vez de `0x410` para MMC2.

### Impacto

- SPL (legacy API) usa `CCU_MMC2_CLK_CFG` directamente desde
  `clock_sun9i.h` → `0x410` → funciona.
- U-Boot proper (DM) llama `get_mclk_offset()` → recibe `0x88` → escribe
  clock en `0x06000090` (campo de otro periférico) → clock de MMC2 no se
  configura → CMD2 falla.

### Fix

```c
if (IS_ENABLED(CONFIG_MACH_SUN9I))
```

### Fix adicional (SPL 8-bit mode)

En `sunxi_mmc_init()` se agregó `IS_ENABLED(CONFIG_MACH_SUN9I)` a la
condición que habilita `MMC_MODE_8BIT` para sdc_no==2, para que SPL también
use 8-bit en MMC2.

### DTS

Se agregaron propiedades al nodo mmc2 en
`arch/arm/dts/sun9i-a80-cubieboard4.dts`:
- `mmc-hs200-1.8v` (DDR mode)
- `broken-cd` (sin CD line)
- `disable-wp`
- `no-sd`

## Debug Methodology

1. Agregar `#define DEBUG` en `sunxi_mmc.c`, `mmc.c`, `spl_mmc.c`,
   `dram_sun9i.c` y subir `CONFIG_SPL_LOGLEVEL=8`.
2. Capturar log U-Boot CONFIG_SPL_LOGLEVEL serial y observar:
   - SPL: CMD1→OCR=0xc0ff8080, CMD2→CID OK, CMD3→RCA, etc. → init OK.
   - U-Boot proper: CMD1→OCR=0xc03f8000 (diferente), CMD2→0xffffffff → fail.
3. Identificar que la única diferencia real entre SPL y U-Boot proper es el
   clock register address.
4. Rastrear a `get_mclk_offset()` → typo `SUN9I_A80` vs `SUN9I`.

## Binary

- MD5: `e323126181e8b1bfca5f3e8371c8426e`
- Tamaño: 477344 bytes
- Compilado con: U-Boot v2025.07-rc4, gcc 12.2.0 (Debian 12 armhf)

## Test Result

eMMC boot sin SD: **EXITOSO**
- SPL → U-Boot proper → kernel → Debian 12 login
- `mmc2: new DDR MMC card at address 0001`
- `mmcblk2: p1 p2`
- Boot completo hasta login

## Archivos modificados

- `drivers/mmc/sunxi_mmc.c`: fix `get_mclk_offset()`, fix 8-bit mode SPL
- `arch/arm/dts/sun9i-a80-cubieboard4.dts`: propiedades mmc2
- `configs/Cubieboard4_defconfig`: `CONFIG_MMC_BROKEN_CD=y` (previo)

## Upstream Note

Esta nota registro originalmente el envio como siguiente paso. Posteriormente,
el parche se envio a `u-boot@lists.denx.de`, con CC a Andre Przywara, Peng Fan
y Jaehoon Chung. Queda hacer seguimiento; no hay Message-ID versionado y no se
debe inventar. El typo afecta todos los boards sun9i-A80:
`CONFIG_MACH_SUN9I_A80` no existe, debe ser `CONFIG_MACH_SUN9I`.
