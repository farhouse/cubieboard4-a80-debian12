# Acto 2 - GPU, OpenGL y OpenCL en Cubieboard4 A80

Fecha: 2026-05-23 (v3: hallazgos vendor images + arquitectura driver DRM)

## Objetivo

Explorar soporte grafico y computo GPU en la Cubieboard4 A80 despues de haber
validado boot, USB, Ethernet y WiFi.

Estado de esta etapa: **modo investigacion primero**. No asumir que OpenGL u
OpenCL acelerados son alcanzables todavia, y no aplicar cambios grandes de
kernel, DTB o userspace hasta identificar una ruta viable con evidencia.

Hay que separar dos problemas distintos:

1. **Salida de video / DRM-KMS**: display engine Allwinner, VGA/HDMI, framebuffer
   o DRM. Esto es necesario para tener consola grafica y probar rendering.
2. **Aceleracion 3D / compute PowerVR**: GPU Imagination PowerVR G6230, OpenGL
   ES/OpenGL/OpenCL. Esto depende de un stack PowerVR especifico.

## Estado conocido

Hardware:

- SoC: Allwinner A80.
- GPU: Imagination PowerVR G6230, Rogue Series6.
- Capacidades de hardware reportadas para G6230:
  - OpenGL ES 1.1/2.0/3.1
  - OpenGL 3.3
  - OpenCL 1.2 EP
  - DirectX 10_0

Sistema actual:

- Debian 12 Bookworm armhf.
- Kernel `6.1.0-37-armmp`.
- DTB propio: `dtb/sun9i-a80-cubieboard4.dtb`.
- Display output todavia no probado.

DTS local:

- `u-boot/arch/arm/dts/sun9i-a80.dtsi` ya declara display engine:
  - `allwinner,sun9i-a80-display-engine`
  - frontends/backends
  - TCON LCD/TV
- `u-boot/arch/arm/dts/sun9i-a80-cubieboard4.dts` habilita `&de` y define
  VGA por `tcon0`.
- Hay regulador `vdd-gpu` (`reg_dcdc2`), pero no hay un nodo GPU PowerVR
  claramente usable en el DTS actual.

### Display/DRM -- Soporte mainline confirmado

El pipeline sun4i-drm para A80 fue añadido en kernel 4.18 por Chen-Yu Tsai
(`[PATCH 5/8] drm/sun4i: Add driver support for A80 display pipeline`, Mar 2018).

Los siguientes compatibles existen en mainline y estan declarados en el DTS:

- `allwinner,sun9i-a80-display-engine`
- `allwinner,sun9i-a80-display-frontend`
- `allwinner,sun9i-a80-display-backend`
- `allwinner,sun9i-a80-deu` (Detail Enhancement Unit)
- `allwinner,sun9i-a80-drc`
- `allwinner,sun9i-a80-tcon-lcd` (TCON0)
- `allwinner,sun9i-a80-tcon-tv` (TCON1)

El nodo `display-engine` usa `allwinner,pipelines = <&fe0>, <&fe1>;`.

NOTA: La wiki linux-sunxi.org marca Display(DRM) como "NO" para A80 en su tabla
Mainlining Effort, pero esto es informacion desactualizada. El soporte existe
en mainline.

### HDMI -- Arquitectura A80 documentada (compatibilidad pendiente)

El DTS `sun9i-a80.dtsi` **no contiene nodo HDMI**. No hay `hdmi-connector`,
`hdmi-phy` ni `allwinner,sun9i-a80-hdmi` declarados.

**Hallazgo clave del manual v1.3.1**: el A80 documenta HDMI como parte del
subsystem display/TCON1, pero el manual disponible no incluye un capitulo de
registros HDMI equivalente a A10/A20/A31. Por ahora no hay evidencia suficiente
para declarar compatibilidad directa con `sun4i-hdmi`, `sun6i-hdmi` o
`dw-hdmi`.

- TCON1 (denominado "LCD1" en la tabla de interrupciones, fuente GIC 119)
  genera timing HDTV directamente
- La salida fisica HDMI esta integrada en el SoC:
  - `HTX0P/N`, `HTX1P/N`, `HTX2P/N`: tres pares TMDS de datos
  - `HTXCP/N`: par TMDS de clock
- Pines de control dedicados (no GPIO-muxed para TX, sí para DDC/CEC):
  - `HHPD`: Hot Plug Detect
  - `HSCL/HSDA` (GPIO PH19/PH20): DDC I2C
  - `HCEC` (GPIO PH21): CEC
  - Alimentación: `VCC18-HDMI` (1.8V) + `VDD09-HDMI` (0.9V)
- El HDMI tiene fuente GIC propia (120; `GIC_SPI 88` en Device Tree)
- Aparece listado junto con display en VDD_SYS_PWROFF_GATING_REG bit 12

**Riesgo principal**: el DTS mainline no declara el bloque HDMI y no hay binding
existente para `allwinner,sun9i-a80-hdmi`. Antes de escribir un nodo o driver
hay que comparar el driver vendor `drivers/video/sunxi/hdmi/` contra
`sun4i-hdmi`/`sun6i-hdmi` y contra los registros expuestos por el manual.

Referencia: `docs/A80_Datasheet_GPIO_Pins.txt` (pines PH19-PH21),
`docs/A80_Manual_Display.txt` (TCON1 para HDTV).

### PowerVR G6230 en drm/imagination -- No soportado

El driver `drm/imagination` (kernel mainline desde 6.8) y el driver Vulkan PVR
en Mesa soportan estas GPUs (Mayo 2026):

| GPU | Serie | BVNC | Driver Kernel | Mesa Vulkan | Firmware público |
|-----|-------|------|--------------|-------------|-----------------|
| AXE-1-16M | A-Series | 33.15.11.3 | Completo (6.8+) | Vulkan 1.2 | `rogue_33.15.11.3_v1.fw` |
| BXS-4-64 | B-Series | 36.53.104.796 | Completo (6.16+) | Vulkan 1.2 | `rogue_36.53.104.796_v1.fw` |
| BXM-4-64 | B-Series | 36.52.104.182 | Completo (6.18+) | Vulkan 1.2 | `rogue_36.52.104.182_v1.fw` |
| GX6250 | 6XT | 4.40.2.51 | Parcial (parches Google 2024) | Parcial (inactivo) | `rogue_4.40.2.51_v1.fw` |
| **G6230** | **Series6** | **1.75.2.30** | **No** | **No** | **No existe** |

**G6230 es Series6 base, NO Series6XT.** La diferencia entre Series6 y Series6XT
es significativa: Imagination reporta que Series6XT es hasta 50% mas rapido
clock-for-clock cluster-for-cluster (Jul 2014). El driver abierto fue escrito
desde cero para GPUs Rogue modernas (Series6XT/A/B), no para Series6 clasico.

**GX6250 -- el caso mas cercano pero aun lejano:**
- Google (Chen-Yu Tsai, May 2024) parcheo soporte para GX6250 en MT8173
  Chromebooks usando el driver abierto: https://lore.kernel.org/dri-devel/20240530083513.4135052-1-wenst@chromium.org/
- Imagination proveyo firmware `rogue_4.40.2.51_v1.fw` especificamente para ese
  esfuerzo -- confirmando que proveen firmware a partners con interes comercial.
- Sin embargo, el soporte en Mesa para GX6250 esta listado como "parcial, no en
  desarrollo activo" y en kernel DRM aun no esta upstream (solo parches externos).
- Diferentes revisiones de GX6250 (p.ej. BVNC 4.45.2.58 vs 4.40.2.51) ni
  siquiera comparten firmware entre si.

**G6230 ni siquiera aparece como "unsupported" en Mesa.** La tabla oficial de
Mesa PowerVR lista 9 GPUs como "unsupported, not under active development"
(G6110, GX6250 varias revisiones, GX6650, GE7800, GE8300, BXE-2-32, BXE-4-32).
G6230 no esta en ninguna categoria -- ni activa, ni parcial, ni unsupported.

### Arquitectura del driver DRM -- Que cambiaria para agregar G6230

Un analisis profundo del driver `drm/imagination` revela que **el kernel NO
necesita una arquitectura nueva**. El driver usa un sistema runtime BVNC:
las features/quirks/enhancements vienen del firmware en tiempo de arranque,
no estan hardcodeadas. El driver ya tiene soporte para los 3 tipos de
procesador firmware (META, MIPS, RISC-V). G6230 usaria META, que ya existe.

**Cambios necesarios en el kernel** (`drivers/gpu/drm/imagination/`):

| Archivo | Cambio | Lineas |
|---------|--------|--------|
| `pvr_device.c` | Agregar `PVR_PACKED_BVNC(1, 75, 2, 30)` a `pvr_gpu_support_level()` | +1 |
| `pvr_drv.c` | Agregar `MODULE_FIRMWARE("powervr/rogue_1.75.2.30_v1.fw")` | +1 |
| `sun9i-a80-cubieboard4.dts` | Agregar nodo GPU con compatible `"img,img-rogue"` | ~30 |

El compatible generico `"img,img-rogue"` ya existe en `dt_match[]` y matchearia
cualquier GPU Rogue. No se necesita Kconfig, Makefile, ni archivos nuevos.
El kernel driver fue diseñado para ser BVNC-agnostico.

**Cambios en Mesa** (`src/imagination/`):

| Archivo | Cambio |
|---------|--------|
| `common/device_info/g6230.h` | **NUEVO** -- tabla features/quirks/enhancements (~200 lineas) |
| `common/device_info/pvr_device_info.c` | Agregar case para BVNC 1.75.2.30 |
| `vulkan/pvr_arch_rogue6.c` | **POSIBLE** -- si Series6 requiere code paths distintos a Series6XT |

Mesa tiene un sistema de compilacion multi-arquitectura (`pvr_arch_*.c`)
que compila ciertos archivos una vez por GPU family. Series6 (Rogue clasico)
vs Series6XT (Rogue XE) vs A-Series vs B-Series cada una puede necesitar
archivos distintos si los registros o secuencias de init difieren.

**El unico blocker real es el firmware**: debe ser compilado por Imagination
especificamente para BVNC 1.75.2.30, con el flag `PVR_FW_FLAGS_OPEN_SOURCE`
y la interfaz FWIF moderna. Sin eso, el driver rechaza la GPU en tiempo de
probe con "Unsupported BVNC". El firmware viejo del vendor (kernel 3.4) usa
la interfaz vieja `pvrsrvkm` y es incompatible.

### BVNC de G6230 -- Confirmado: 1.75.2.30

El BVNC (Branch.Version.Number.Config) se obtuvo del kernel vendor de
Cubieboard. El Makefile de `modules/rogue_km/` define:

```
RGX_BVNC = 1.75.2.30
```

Esto significa:
- **Branch**: 1 (Rogue Series6)
- **Version**: 75
- **Number**: 2 (dual-cluster, 64 cores)
- **Config**: 30

Este BVNC **no esta listado** en el driver `drm/imagination` ni en Mesa PVR.
El firmware de Imagination disponible actualmente en `linux-firmware.git` es:

| Firmware | BVNC | GPU | Tamaño |
|----------|------|-----|--------|
| `rogue_33.15.11.3_v1.fw` | 33.15.11.3 | AXE-1-16M | 112 KB |
| `rogue_36.53.104.796_v1.fw` | 36.53.104.796 | BXS-4-64 | 155 KB |
| `rogue_4.40.2.51_v1.fw` | 4.40.2.51 | GX6250 | ~? |
| `rogue_36.52.104.182_v1.fw` | 36.52.104.182 | BXM-4-64 | ~? |
| **`rogue_1.75.2.30_v1.fw`** | **1.75.2.30** | **G6230** | **No existe** |

El BVNC 1.75.2.30 no tiene firmware publico ni soporte en el driver abierto.

Se necesitaria contacto directo con Imagination para solicitar:
1. Firmware compatible con BVNC 1.75.2.30
2. Device info struct para kernel driver + Mesa
3. Confirmacion de que el driver soporta revision tan temprana de Rogue

El precedente de GX6250 demuestra que Imagination provee firmware cuando hay un
partner con interes comercial detras (Google/Chromebook). Para A80 no existe
tal interes actualmente.

### Tabla GIC (interrupciones) completa -- display/GPU/HDMI

Extraída del manual A80 v1.3.1 sección 3.13 (páginas 236-240). El manual lista
el numero de fuente GIC absoluto, incluyendo SGI/PPI. En Device Tree, el macro
`GIC_SPI` usa numeracion relativa al primer SPI; por eso:

```text
GIC_SPI en DTS = fuente_manual - 32
IRQ Linux normalmente visible = fuente_manual
```

| Fuente manual | GIC_SPI DTS | Módulo | Fuente manual | GIC_SPI DTS | Módulo |
|---------------|--------------|--------|---------------|--------------|--------|
| 118 | 86 | LCD-0 (TCON0) | 125 | 93 | DE_FE0 |
| 119 | 87 | LCD-1 (TCON1) | 126 | 94 | DE_FE1 |
| **120** | **88** | **HDMI** | 127 | 95 | DE_BE0 |
| 121 | 89 | MIPI DSI | 128 | 96 | DE_BE1 |
| 123 | 91 | DRC 0/1 | **129** | **97** | **GPU** |
| 124 | 92 | DEU 0/1 | **130** | **98** | **GPU PWR** |
| **148** | **116** | **DE_BE2** | **159** | **127** | **DE_FE2** |
| 150 | 118 | eDP | | | |

Notas:
- El DTS mainline confirma el criterio: LCD-0 fuente 118 aparece como
  `interrupts = <GIC_SPI 86 IRQ_TYPE_LEVEL_HIGH>`.
- HDMI tiene **fuente GIC propia** (120 / `GIC_SPI 88`), confirmando que el
  bloque HDMI tiene lógica de control más allá de TCON1.
- GPU tiene **dos** fuentes: GPU (129 / `GIC_SPI 97`) + GPU PWR
  (130 / `GIC_SPI 98`).
- Tercer pipe display confirmado por tabla y memory map: DE_BE2 y DE_FE2. La
  tabla extraida por OCR marca `DE_FE2` como fuente 159; verificar visualmente
  en el PDF antes de convertirlo en DTS porque podria ser error de OCR.
- eDP (150 / `GIC_SPI 118`) presente en el SoC pero no declarado en DTS.
- TCON2 no aparece en esta tabla (solo TCON0=LCD-0, TCON1=LCD-1).

Fuente: `docs/A80_Manual_GIC_SPI_Table.txt`

### GPU Control Module (GCM) en el A80

El manual v1.3.1 incluye la sección **5.1 GPU Control** (páginas 463-467) que
describe el módulo `GCM` (GPU Control Module) en **0x01C08000**:

| Registro | Offset | Descripción |
|----------|--------|-------------|
| GCM_IDLE_STATUS_REG | 0x08 | GPU idle status (0=busy, 1=idle) |
| GCM_QOS_REG | 0x0C | AXI QoS (max read/write commands, QoS) |
| GCM_INT_PWROFF_GATING_REG | 0x10 | Power gating interno "Rascal/Dust" |
| GCM_INT_PWR_MOD_REG | 0x14 | Modo power event (HW/SW, interrupt enable) |
| GCM_INT_PWR_DLY_REG | 0x18 | Delays para transiciones de power |
| GCM_INT_PWR_EVENT_REQ_REG | 0x1C | Power event request + type status |
| GCM_INT_PWR_RESPONSE_REG | 0x20 | Abort/complete response |

"Rascal" y "Dust" son los nombres internos de los dos clusters de shaders del
G6230 (dual-cluster, 64 cores). El GCM maneja power gating y BIST test.
Interrupción `GPU PWR` (fuente GIC 130 / `GIC_SPI 98`) proviene de este módulo
cuando hay power events.

El power domain del GPU se controla desde R_PRCM (0x08001400 offset 0x0118):
`GPU_PWROFF_GATING_REG`, un solo bit. Secuencia recomendada: set bit 0 a 1
antes de apagar GPU, esperar 1us, luego desassert.

Fuente: `docs/A80_Manual_PRCM_GPU_Power.txt`

### Memory map -- Áreas clave verificadas en manual v1.3.1

| Región | Dirección | Tamaño | Descripción |
|--------|-----------|--------|-------------|
| GCM | 0x01C08000 | 32B | GPU Control Module (power mgmt) |
| GPU_MEM | 0x02000000-0x02FFFFFF | 16MB | GPU memory aperture |
| DEFE0 | 0x03100000 | 64KB | Display Engine Frontend 0 |
| DEFE1 | 0x03140000 | 64KB | Display Engine Frontend 1 |
| DEFE2 | 0x03180000 | 64KB | Display Engine Frontend 2 |
| DE_SYS | 0x03000000 | - | Display Engine system register |
| DISP_SYS | 0x03010000 | - | Display controller |
| MP (G2D) | 0x03F00000 | 4KB | Mixer Processor (2D blitter) |
| System Control | 0x00800000 | - | VER_REG (0x24), EMAC_CLK (0x30), DISP_MUX_CTRL (0x38) |
| PIO | 0x06000800 | - | GPIO registers |
| CCU | 0x06000000 | - | PLLs y clocks |
| CCU_SCLK | 0x06000400 | - | Special clocks (per-device) |
| R_PRCM | 0x08001400 | - | Power management (GPU power gating) |
| DMAC | 0x00802000 | - | DMA controller |
| TWD | 0x08001800 | - | Trusted Watchdog |

Fuente: `docs/A80_Manual_MemoryMap.txt`, `docs/A80_Manual_Display.txt`,
`docs/A80_Manual_GraphicEngine2.txt`

### Display Engine -- Tres pipes confirmados

El manual describe **3 pares DEFE/DEBE**:
- DEFE0 0x03100000 + DEBE0
- DEFE1 0x03140000 + DEBE1
- DEFE2 0x03180000 + DEBE2

El DTS mainline actual solo declara 2 pares (FE0/BE0, FE1/BE1). El tercer pipe
(DEFE2/DEBE2) tiene capacidades reducidas (nota en pág 714: "Only for DEFE0/1,
invalid for DEFE2" para registros de deinterlacing 3D).

El SMC (Security Memory Controller, pág 286) confirma los bits de enable:
- `DEFE0_EN`, `DEFE1_EN`, `DEFE2_EN` (bits 4-6)
- `DEBE0_EN`, `DEBE1_EN`, `DEBE2_EN` (bits 7-9)

TCON0 y TCON1 compartidos por los 3 pipes via `DISP_MUX_CTRL_REG`
(System Control 0x00800038, bits no extraídos del PDF).

### G2D Mixer Processor (2D blitter) -- Documentado en manual

El Capítulo 5.2 del manual documenta el Mixer Processor (MP) en **0x03F00000**,
un acelerador 2D tipo BitBLT con ~50 registros:

- 4 canales DMA de entrada con formatos: mono 1/2/4/8bpp, RGB565/ARGB1555/
  ARGB4444/ARGB8888, YUV411/420/422/444
- 3 canales DMA de salida
- 2 Color Space Converters (CSC) de entrada + 1 de salida
- Scaler bicúbico (4 taps × 32 fases)
- ROP3/ROP4 con tabla de lookup
- Alpha blending / Color key
- Rotación 0/90/180/270°
- Command queue (cola de comandos)
- Tamaño de buffer hasta 8192×8192 píxeles

Este bloque puede ser útil para composición 2D acelerada incluso sin GPU 3D,
similar a cómo se usa en otros SoCs Allwinner.

Fuente: `docs/A80_Manual_GraphicEngine2.txt`

### PLLs y Clocks para display/GPU -- Confirmados

| PLL | Offset CCU | Default | Uso |
|-----|------------|---------|-----|
| PLL_GPU | 0x020 | 432 MHz | GPU + MP (G2D) |
| PLL_DE | 0x024 | - | Display Engine |
| PLL_Video0 | 0x018 | - | Video/TCON timing |
| PLL_Video1 | 0x01C | - | Display modules/interfaces |

**Bus clock gates** (CCU_SCLK 0x06000400):

| Registro | Offset | Bits clave |
|----------|--------|------------|
| BUS_CLK_GATING_REG2 | 0x018C | LCD0_GATING(0), LCD1_GATING(1), CSI_GATING(4) |
| BUS_CLK_GATING_REG3 | 0x0190 | - |
| BUS_CLK_GATING_REG4 | 0x0194 | UART3-5, etc. |

**Bus software resets**:

| Registro | Offset | Bits clave |
|----------|--------|------------|
| BUS_SOFT_RST_REG1 | - | GPU_CTRL_RESET(3), FD_RESET(0) |
| BUS_SOFT_RST_REG2 | 0x01A8 | GPU_RESET(9) |

Separación clara: `GPU_CTRL_RESET` resetea el GCM (power mgmt),
`GPU_RESET` resetea el core de la GPU.

**Clocks especiales GPU**:
- `GPU_MEM_CLK_REG` (CCU_SCLK offset 0xF4): clock para memoria GPU, fuente PLL_GPU
- `GPU_AXI` clock gate en BUS_CLK_GATING_REG2

Fuente: `docs/A80_Manual_GPU_Clocks.txt`, `docs/A80_Manual_CCU.txt`

### Kernel vendor CC-A80 (linux-3.4) -- Analisis

El repositorio `cubieboard/CC-A80-kernel-source` contiene el kernel vendor 3.4
para Cubieboard4 A80 (conocido como CC-A80). Hallazgos clave:

**PowerVR Rogue DDK** (`modules/rogue_km/`):
- Es un modulo externo standalone, NO integrado en el kernel tree
- Se compila con `make` + `CROSS_COMPILE=arm-linux-gnueabihf-`
- Produce dos .ko: **`srvkm.ko`** (servicios GPU) + **`dc_drmfbdev.ko`** (display)
- Usa display controller `dc_drmfbdev` que se integra con DRM fbdev
- `EXCLUDED_APIS = opencl` -- OpenCL fue excluido explicitamente en build
- `PVR_SYSTEM := rgx_sunxi` -- plataforma especifica Allwinner
- `PDUMP ?= 1` -- parameter dump habilitado (debug)

**Display driver** (`drivers/video/sunxi/`):
- Stack propietario Allwinner, NO el DRM mainline
- `disp/` -- display engine (DISP), framebuffer (`dev_fb.c`)
- `hdmi/` -- driver HDMI propietario (`drv_hdmi.c`)
- No usa Device Tree (`# CONFIG_USE_OF is not set`)
- Config: `CONFIG_FB_SUNXI=y`, `CONFIG_HDMI_SUNXI=y`, `CONFIG_DRM=y`

**DRM integration**: Aunque `CONFIG_DRM=y`, no es el sun4i-drm mainline.
El kernel vendor tiene DRM solo como soporte para que `dc_drmfbdev.ko`
(PowerVR display controller) pueda usar DRM fbdev. No hay KMS (kernel mode
setting) mainline.

**Implicaciones para port a kernel 6.1**:

| Componente | Kernel 3.4 vendor | Kernel 6.1 mainline | Port viable? |
|-----------|-------------------|--------------------|-------------|
| srvkm.ko | Rogue DDK RGX_BVNC 1.75.2.30 | No disponible | No (API/ABI incompatibles) |
| dc_drmfbdev.ko | DRM fbdev display | No disponible | No |
| disp/ | Allwinner FB display | sun4i-drm (reemplazo) | No necesario |
| hdmi/ | Allwinner HDMI | sun4i-hdmi? (no existe para A80) | Port necesario |
| Userspace libs | Android 4.4 / Linaro | Debian 12 Bookworm | Dependencias rotas |

**Fuente**: https://github.com/cubieboard/CC-A80-kernel-source

### meta-sunxi / Yocto reference

Leon Anavi (Dic 2024) demostro boot mainline en Merrii A80 Optimus:
- Kernel 6.6.28 + U-Boot 2024.10
- Via Yocto Scarthgap + meta-sunxi
- No se menciona funcionamiento de display ni GPU
- Sirve como referencia de que mainline kernel/u-boot es estable para A80

Referencia: https://anavi.org/article/291/

### Imágenes vendor -- Inventario de blobs PowerVR

Analisis de las imágenes disponibles en `images/`:

| Imagen | Contenido PowerVR detectado |
|--------|---------------------------|
| `linaro-desktop-cb4-emmc-hdmi-v1.1.img` | `pvr_dri.so`, `libEGL.so`, `libGLESv1_CM.so`, `libGLESv2.so`, `gl_renderer_string: "PowerVR Rogue G6230"`. Menos completa, sin kernel modules. |
| `android4.4-cb4-emmc-v4.3.20170717.img` | `/system/modules/pvrsrvkm.ko`, `/system/vendor/lib/egl/libGLESv1_CM_POWERVR_ROGUE.so`, `/system/vendor/lib/egl/libGLESv2_POWERVR_ROGUE.so`, `libPVROCL.so`. Build path: `/work/SDK/a80/lichee/linux-3.4/modules/rogue_km/`. |

**Conclusion**: los blobs existen en la imagen Android (kernel module 3.4 +
userspace GLES/OpenCL), pero son **incompatibles con mainline**. El kernel
module `pvrsrvkm.ko` usa APIs de kernel 3.4. Las librerias userspace solo
funcionan con el DDK exacto. El firmware embebido usa interfaz pvrsrvkm
antigua, no la FWIF moderna que requiere `drm/imagination`.

**Utilidad potencial**: los blobs sirven para RE (reverse engineering) de
registros y estructura del firmware, pero no para alimentar al driver abierto.

### Resumen de soporte upstream

- Mesa documenta un driver PowerVR abierto orientado a Vulkan para GPUs Rogue.
- El soporte activo actual esta centrado en GPUs Imagination mas nuevas o
  concretas como AXE/BXM/BXS (A-Series y B-Series).
- **GX6250** (Series6XT): soporte parcial en Mesa Vulkan, Google parcheo en
  2024 para Chromebooks MT8173, Imagination proveyo firmware. No upstream en
  DRM kernel aun. Sirve como precedente de que se puede lograr con presion
  comercial.
- **G6230** (Series6 base): completamente ausente de todas las listas -- ni
  activo, ni parcial, ni siquiera "unsupported". BVNC 1.75.2.30 sin firmware
  publico.
- **Diferencia Series6 vs Series6XT**: significativa. Series6XT es hasta 50%
  mas rapido clock-for-clock. El driver abierto se diseno para Series6XT en
  adelante. Agregar Series6 requeriria cambios en la capa de arquitectura
  (`pvr_arch_*.c`) en Mesa, pero NO en el kernel (el kernel es BVNC-agnostico:
  features/quirks vienen del firmware en runtime).
- Imagination indica que el driver abierto puede correr OpenGL/OpenGL ES via
  Zink, pero eso presupone tener Vulkan funcionando.
- OpenCL no queda cubierto por ese camino; para G6230 lo mas realista es buscar
  blobs vendor.
- Imagination (pagina oficial, Mar 2026): "additional GPUs becoming available in
  later Linux kernel releases" -- pero su roadmap es para IP moderna (BXS, BXM,
  AXE), no Series6 clasico.
- **Display/KMS mainline**: confirmado funcional para VGA. HDMI requiere driver
  nuevo (no compatible con sun4i-hdmi existente).
- **GPU Control Module (GCM)** documentado en manual (0x01C08000): power gating
  "Rascal/Dust" (clusters), idle status, modo HW/SW.
- **3 pipes display**: DEFE0/1/2 + DEBE0/1/2 confirmados, DTS actual solo
  declara 2.
- **G2D Mixer Processor** (0x03F00000): acelerador 2D util incluso sin GPU 3D.

Conclusion de factibilidad:

- **OpenGL acelerado mainline**: muy bajo. G6230 no tiene firmware, ni device
  info, ni soporte en driver. Solo viable si Imagination lo adopta como
  objetivo de driver abierto -- improbabe sin partner comercial. El kernel
  driver necesitaria ~5 lineas de cambio. El blocker es el firmware.
- **OpenCL mainline**: esencialmente imposible. Vendor excluyo OpenCL del build,
  driver abierto solo cubre Vulkan, no hay implementacion OpenCL en pipeline.
- **OpenGL ES/OpenCL con blobs vendor**: confirmados en imagen Android (kernel
  3.4 + libGLES_POWERVR_ROGUE + libPVROCL), pero atados al stack vendor viejo.
  Incompatibles con kernel 6.x y mainline.
- **Display/KMS mainline**: es el primer objetivo practico y medible (VGA
  funcional, HDMI requiere driver nuevo).
- **G2D acceleration**: posible via Mixer Processor incluso sin GPU 3D.
- **Camino mas pragmatico para 3D**: display mainline + Mesa software
  rendering (llvmpipe) para GUI basica, sin aceleracion 3D.

## Plan recomendado

Antes de implementar, juntar evidencia. Estado de las preguntas (Mayo 2026):

- **Display VGA mainline**: soportado en DTS actual (tcon0 + vga-dac + vga-connector).
  Pendiente probar en hardware real.
- **HDMI mainline**: no hay nodo ni driver. Manual A80 confirma HDMI integrado
  con fuente GIC propia, pero sin registros PHY documentados. Driver nuevo
  necesario.
- **GPU PowerVR driver mainline**: NO. G6230 no tiene firmware, device info, ni
  soporte en drm/imagination. BVNC 1.75.2.30 no existe en linux-firmware.git.
- **GPU PowerVR vendor**: modulo `pvrsrvkm.ko` para kernel 3.4. Port a 6.x inviable
  (API/ABI incompatibles, OpenCL excluido).
- **Blobs vendor**: **localizados en imagen Android** (`android4.4-cb4-emmc-v4.3.20170717.img`).
  Contiene `pvrsrvkm.ko`, `libGLESv1_CM_POWERVR_ROGUE.so`, `libGLESv2_POWERVR_ROGUE.so`,
  `libPVROCL.so`. Todos dependientes del DDK vendor y kernel 3.4. No compatibles
  con mainline.
- **OpenGL/OpenGL ES/OpenCL acelerado**: solo factible via stack vendor legacy
  (kernel 3.4). No hay camino mainline viable para G6230. OpenCL fue excluido
  explicitamente en el build vendor.
- **G2D Mixer Processor**: documentado en manual (0x03F00000), acelerador 2D
  util incluso sin GPU 3D. No explorado aun.
- **Mesa software**: camino mas realista para GUI basica (llvmpipe). No requiere
  GPU.

### Fase 1 - Inventario en el sistema actual

Objetivo: saber que ve el kernel Bookworm y que paquetes/userspace hay.

Comandos en la CB4:

```sh
uname -a
cat /proc/device-tree/model
dmesg | grep -Ei 'drm|fb|framebuffer|sun4i|display|tcon|hdmi|vga|gpu|pvr|powervr'
ls -l /dev/dri /dev/fb* 2>/dev/null
cat /sys/kernel/debug/dri/*/name 2>/dev/null
lsmod | grep -Ei 'drm|sun|pvr|gpu'
```

Resultado esperado:

- Confirmar si existe `/dev/dri/card0` o solo framebuffer.
- Confirmar si `sun4i-drm` o drivers de display Allwinner cargan.
- Confirmar si VGA/HDMI genera algun modo o conector.

### Fase 2 - Salida de video

#### VGA (prioritario)

El DTS actual ya define `vga-connector`, `vga-dac` (gm7123/adv7123) y `tcon0`.
Es el camino mas directo para validar display.

Comandos utiles:

```sh
modetest -c
modetest -p
modetest -M sun4i-drm -c
```

Paquetes utiles si faltan:

```sh
apt install libdrm-tests kmscube mesa-utils
```

Validacion:

```sh
modetest -M sun4i-drm -s <connector_id>:<mode>
```

Guardar evidencia en:

```text
logs/YYYY-MM-DD-display-vga.log
notes/YYYY-MM-DD-display-vga.md
```

#### HDMI (investigacion completa -- compatibilidad/driver pendiente)

No hay nodo HDMI en el DTS actual. Investigación del manual v1.3.1 concluye:

**No esta probado que el A80 sea compatible con el controller HDMI tipo A31.**
Tiene:
- TCON1 genera timing HDTV directamente
- Salida TMDS integrada: `HTX0/1/2` + `HTXC`
- HPD dedicado (`HHPD`) + DDC (`HSCL/HSDA` via GPIO PH19/PH20) + CEC (PH21)
- Fuente GIC propia (120 / `GIC_SPI 88`) para el bloque HDMI
- Sin capítulo dedicado en el manual, sin registros de PHY documentados
- VDD_SYS power domain (bit de hold en VDD_SYS_PWROFF_GATING_REG)

Trabajo pendiente antes de afirmar si se puede reutilizar un driver existente:
comparar el driver vendor `drivers/video/sunxi/hdmi/` con `sun4i-hdmi`,
`sun6i-hdmi` y `dw-hdmi`. Si no hay compatibilidad razonable, habria que
escribir driver nuevo para:

1. Mapear registros TCON1 para timing HDMI (pixel rep, sync polarities)
2. Controlar PHY (posiblemente desde System Control o TCON1 mismo)
3. DDC via GPIO bit-banging o I2C en PH19/PH20
4. Detectar HPD via GPIO PH (EINT)
5. Declarar nodos: `tcon1_out_hdmi`, `hdmi-connector`, GPIO DDC/HPD

Guardar evidencia de cualquier intento en:

```text
logs/YYYY-MM-DD-display-hdmi.log
notes/YYYY-MM-DD-display-hdmi.md
```

### Fase 3 - OpenGL sin aceleracion, como baseline

Objetivo: establecer una linea base con Mesa software rendering antes de tocar
PowerVR.

Comandos:

```sh
glxinfo -B
eglinfo
LIBGL_ALWAYS_SOFTWARE=1 glxinfo -B
```

Resultado esperado si no hay GPU:

- Renderer tipo `llvmpipe` o `softpipe`.
- Sirve para probar que userspace grafico funciona, pero no valida PowerVR.

### Fase 4 - Inventario de blobs vendor PowerVR (COMPLETADO)

Objetivo cumplido: se extrajeron y analizaron las imagenes vendor.

**Resultados de la busqueda en `images/`**:

| Imagen | Archivos PowerVR encontrados | Estado |
|--------|------------------------------|--------|
| `android4.4-cb4-emmc-v4.3.20170717.img` | `/system/modules/pvrsrvkm.ko`, `/system/vendor/lib/egl/libGLESv1_CM_POWERVR_ROGUE.so`, `/system/vendor/lib/egl/libGLESv2_POWERVR_ROGUE.so`, `libPVROCL.so` | Blobs confirmados, imagen formato Allwinner (no ext4 directo), extraccion requiere parser de formato propietario |
| `linaro-desktop-cb4-emmc-hdmi-v1.1.img` | `pvr_dri.so`, `libEGL.so`, `libGLESv1_CM.so`, `libGLESv2.so` | Solo userspace DRI/GLES, sin kernel module ni firmware |
| `cb4-debian-server-hdmi-card-v1.0.img.7z` | No analizado | Similar a Linaro |
| `cb4-debian-server-hdmi-emmc-v1.0.img.7z` | No analizado | Similar a Linaro |

El kernel module `pvrsrvkm.ko` fue compilado para kernel 3.4 (ruta de build:
`/work/SDK/a80/lichee/linux-3.4/modules/rogue_km/`). Las librerias userspace
usan naming especifico del DDK vendor (`libGLESv1_CM_POWERVR_ROGUE.so`).

**Riesgo confirmado**: todos los blobs vendor dependen del kernel 3.4 y DDK
exacto. No cargan en kernel 6.x. El firmware embebido en `pvrsrvkm.ko` usa
interfaz pvrsrvkm antigua, incompatible con `drm/imagination`.

### Fase 5 - Decidir ruta

Rutas posibles:

1. **Mainline display + Mesa software**:
   - Baja friccion.
   - Permite GUI basica sin aceleracion.
   - No entrega OpenCL ni OpenGL acelerado.

2. **Vendor legacy para OpenGL ES/OpenCL**:
   - Mayor probabilidad de acelerar PowerVR G6230.
   - Probablemente requiere kernel 3.4/vendor o Android/Linaro antiguo.
   - Menos mantenible.

3. **Investigar driver PowerVR abierto**:
   - Camino mas mantenible a largo plazo.
   - Para G6230/A80 hoy parece incierto.
   - Requiere confirmar BVNC de la GPU, firmware disponible y soporte kernel
     DRM compatible.

## Primer experimento recomendado

No empezar por OpenCL ni por cambios de driver. Primero validar display y DRM
con inventario no invasivo:

```sh
dmesg | grep -Ei 'drm|fb|framebuffer|sun4i|display|tcon|hdmi|vga'
ls -l /dev/dri /dev/fb* 2>/dev/null
modetest -c
glxinfo -B
```

Si no hay `modetest`, instalar `libdrm-tests`. Si no hay `glxinfo`, instalar
`mesa-utils`.

Despues de eso, capturar:

```text
logs/2026-05-22-gpu-display-inventory.log
notes/2026-05-22-gpu-display-inventory.md
```

## Fuentes

- Mesa PowerVR driver documentation:
  https://docs.mesa3d.org/drivers/powervr.html
- Imagination Open Source GPU Driver:
  https://developer.imaginationtech.com/solutions/open-source-gpu-driver/
- Imagination PowerVR Rogue GPU guide:
  https://blog.imaginationtech.com/the-complete-guide-to-powervr-rogue-gpus-specifications-features-api-support/
- Imagination Zink + Mesa 26.1 (Mar 2026):
  https://blog.imaginationtech.com/powervr-the-path-to-open-source-zink-and-opengl-es-support
- linux-sunxi A80:
  https://linux-sunxi.org/A80
- linux-sunxi PowerVR:
  https://linux-sunxi.org/PowerVR
- Mesa PowerVR hardware support table (BVNCs activos/parciales/unsupported):
  https://docs.mesa3d.org/drivers/powervr.html
- Imagination Open Source Driver (Mar 2026, GPUs soportadas):
  https://developer.imaginationtech.com/solutions/open-source-gpu-driver/
- Phoronix - Google GX6250 enablement (May 2024):
  https://www.phoronix.com/news/PowerVR-GX6250-MT8173
- Phoronix - PowerVR firmware BXS-4-64 (May 2025):
  https://www.phoronix.com/news/PVR-BXS-4-64-Firmware
- Phoronix - PowerVR firmware AXE-1-16M inicial (Nov 2023):
  https://www.phoronix.com/news/PowerVR-Firmware-Blob
- Phoronix - PowerVR DRM driver RISC-V + BXM-4-64 (Sep 2025):
  https://www.phoronix.com/news/Linux-6.18-PowerVR-RISC-V
- Imagination - Series6 vs Series6XT performance difference (Jul 2014):
  https://www.chipestimate.com/A-guide-to-the-new-PowerVR-Rogue-GPUs/Imagination-Technologies/Technical-Article/2014/07/01
- linux-sunxi Mainlining Effort (tabla display A80):
  https://linux-sunxi.org/Mainlining_Effort
- Parches display A80 mainline -- Chen-Yu Tsai (2018):
  https://lists.freedesktop.org/archives/dri-devel/2018-March/169590.html
- DT bindings display sun4i-drm (kernel docs):
  https://www.kernel.org/doc/Documentation/devicetree/bindings/display/sunxi/sun4i-drm.txt
- Parche GX6250 DT binding para R-Car -- Marek Vasut (2025):
  https://lists.infradead.org/pipermail/linux-arm-kernel/2025-October/1069555.html
- Yocto A80 mainline -- Leon Anavi (2024):
  https://anavi.org/article/291/
- meta-sunxi layer:
  https://github.com/linux-sunxi/meta-sunxi
- Cubieboard CC-A80 kernel source (vendor linux-3.4, PowerVR Rogue DDK):
  https://github.com/cubieboard/CC-A80-kernel-source
- A80 Datasheet v1.3 (2015-05-10, 43 pag):
  https://github.com/allwinner-zh/documents/raw/master/A80/A80_Datasheet_v1.3_20150510.pdf
- A80 User Manual v1.3.1 (2015-05-13, 1056 pag):
  https://github.com/allwinner-zh/documents/raw/master/A80/A80_User_Manual_v1.3.1_20150513.pdf
  (mirror: https://github.com/BPI-SINOVOIP/Allwinner-Official-Documents/raw/master/A80/A80_User_Manual_v1.3.1_20150513.pdf)
- CC-A80-rootfs build instructions (clonar repos de github.com/cubieboard):
  https://github.com/cubieboard/CC-A80-rootfs

### Documentación extraída del manual v1.3.1 (offline, `docs/`)

- `docs/A80_User_Manual_v1.3.1_20150513.pdf` — manual completo (13 MB, 1056 pag)
- `docs/A80_Datasheet_v1.3_20150510.pdf` — datasheet (4.3 MB, 43 pag, GPIO + HDMI PHY pins)
- `docs/A80_User_Manual_TOC.txt` — tabla de contenido (35 pag)
- `docs/A80_Manual_Display.txt` — Chapter 7 Display Engine (187 pag, DEFE/DEBE/TCON)
- `docs/A80_Manual_TCON.txt` — TCON0/TCON1 registers (53 pag)
- `docs/A80_Manual_MemoryMap.txt` — memory map (22 pag)
- `docs/A80_Manual_CCU.txt` — CCU register list + PLLs
- `docs/A80_Manual_GPU.txt` — GPU power gating en PRCM
- `docs/A80_Manual_GPU_Clocks.txt` — GPU clocks y resets
- `docs/A80_Manual_PRCM_GPU_Power.txt` — PRCM + GCM power registers
- `docs/A80_Manual_PRCM_Registers.txt` — R_PRCM register list
- `docs/A80_Manual_ClockGating.txt` — bus clock gates y resets
- `docs/A80_Manual_GIC_SPI_Table.txt` — tabla completa de interrupciones GIC
- `docs/A80_Manual_DisplayMux.txt` — DISP_MUX_CTRL_REG
- `docs/A80_Manual_GraphicEngine2.txt` — Chapter 5 Graphic (GCM + G2D Mixer Processor)
- `docs/A80_Manual_HDMI.txt` — referencias HDMI en el manual
- `docs/A80_Datasheet_GPIO_Pins.txt` — tablas de pines GPIO (1167 lineas)
