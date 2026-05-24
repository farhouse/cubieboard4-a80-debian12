# Análisis pendiente del HDMI vendor A80

Fecha: 2026-05-23

## Objetivo

Separar la investigación HDMI del trabajo PowerVR/GPU. El objetivo es decidir,
con evidencia del kernel vendor y del manual A80 v1.3.1, si el HDMI del A80
puede reutilizar algún driver mainline existente o si requiere un driver nuevo.

## Estado actual

- `sun9i-a80.dtsi` declara TCON1 (`allwinner,sun9i-a80-tcon-tv`) pero no declara
  nodo HDMI, HDMI PHY ni `hdmi-connector`.
- `sun9i-a80-cubieboard4.dts` solo cablea `tcon0` hacia VGA.
- El manual A80 v1.3.1 lista:
  - LCD-1/TCON1 como fuente GIC 119 (`GIC_SPI 87` en DTS).
  - HDMI como fuente GIC 120 (`GIC_SPI 88` en DTS).
  - `VDD_SYS_PWROFF_GATING_REG` bit 12 para display/HDMI/GPIO hold.
- El datasheet A80 v1.3 lista la salida HDMI fisica:
  - `HTX0P/N`, `HTX1P/N`, `HTX2P/N`: TMDS data.
  - `HTXCP/N`: TMDS clock.
  - `HHPD`: hot plug detect.
  - `HSCL/HSDA`: DDC, mux en PH19/PH20.
  - `HCEC`: CEC, mux en PH21.
  - `VCC18-HDMI` y `VDD09-HDMI`.

## Evidencia vendor disponible

Las imagenes vendor usan FEX/script.bin y kernel 3.4.39. En
`/private/tmp/cb4-analysis/card-root/root/boot-file/hdmi_sys_config.fex`:

- `screen1_output_type = 3` selecciona HDMI.
- `screen1_output_mode = 10` selecciona 1080p60.
- `[hdmi_para] hdmi_used = 1`.

El FEX no da direcciones ni secuencia de PHY; eso probablemente vive en el
kernel vendor `drivers/video/sunxi/hdmi/`.

## Preguntas a responder

1. ¿Qué direcciones base usa el driver HDMI vendor?
2. ¿El vendor usa un bloque compatible con A10/A20/A31 (`sun4i-hdmi`/`sun6i-hdmi`)
   o una variante propia de A80?
3. ¿La lógica HDMI está dentro de TCON1, dentro de un bloque HDMI separado, o
   repartida entre TCON1, System Control y PHY?
4. ¿Cómo implementa HPD y DDC?
5. ¿Qué clocks, resets y regulators activa antes de generar señal?
6. ¿Qué registros toca para el PHY/TMDS?
7. ¿Puede modelarse como bridge/connector DRM estándar o requiere un encoder
   sun4i específico?

## Próximos pasos

1. Obtener o inspeccionar `CC-A80-kernel-source/drivers/video/sunxi/hdmi/`.
2. Buscar en ese árbol:

```sh
rg -n "hdmi|hpd|ddc|edid|phy|tmds|0x03c1|0x03c|0x0600|0x0080" drivers/video/sunxi/hdmi drivers/video/sunxi/disp
```

3. Extraer:
   - tabla de registros;
   - secuencia de init;
   - manejo HPD/DDC/EDID;
   - clocks/resets/regulators;
   - relación con TCON1.
4. Comparar contra drivers mainline:
   - `drivers/gpu/drm/sun4i/sun4i_hdmi*`
   - `drivers/gpu/drm/sun4i/sun6i_hdmi*`
   - `drivers/gpu/drm/bridge/synopsys/dw-hdmi*`
5. Recién después decidir si crear un nodo DTS experimental o documentar que
   HDMI requiere driver nuevo.

## Criterio de avance

No agregar un nodo HDMI al DTB estable hasta tener al menos una de estas dos
evidencias:

- compatibilidad clara con un driver mainline existente; o
- mapa mínimo de registros/secuencia suficiente para un driver experimental.
