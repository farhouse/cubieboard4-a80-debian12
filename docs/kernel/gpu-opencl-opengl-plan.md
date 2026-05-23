# Acto 2 - GPU, OpenGL y OpenCL en Cubieboard4 A80

Fecha: 2026-05-23 (actualizado con hallazgos manual v1.3.1)

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

### HDMI -- Arquitectura A80 documentada (no compatible con sun4i-hdmi)

El DTS `sun9i-a80.dtsi` **no contiene nodo HDMI**. No hay `hdmi-connector`,
`hdmi-phy` ni `allwinner,sun9i-a80-hdmi` declarados.

**Hallazgo clave del manual v1.3.1**: El HDMI del A80 NO usa un controller HDMI
separado como el A31 (sun6i-hdmi). En cambio:

- TCON1 (denominado "LCD1" en la tabla de interrupciones, SPI 119) genera
  timing HDTV directamente
- El HDMI PHY es un bloque analógico integrado en el SoC con un solo par
  diferencial de salida: `HTX0N/HTX0P`
- Pines de control dedicados (no GPIO-muxed para TX, sí para DDC/CEC):
  - `HTX0N/HTX0P`: un par diferencial de salida TMDS (fijo, no pinmux)
  - `HHPD`: Hot Plug Detect
  - `HSCL/HSDA` (GPIO PH19/PH20): DDC I2C
  - `HCEC` (GPIO PH21): CEC
  - Alimentación: `VCC18-HDMI` (1.8V) + `VDD09-HDMI` (0.9V)
- El HDMI tiene SPI propio (120) en el GIC
- Aparece listado junto con display en VDD_SYS_PWROFF_GATING_REG bit 12

**El driver sun4i-hdmi no es compatible**. El PHY del A80 es mucho más simple
que el controller completo que tienen A10/A20/A31. Requiere un driver nuevo
que maneje TCON1 + PHY integrado.

Referencia: `docs/A80_Datasheet_GPIO_Pins.txt` (pines PH19-PH21),
`docs/A80_Manual_Display.txt` (TCON1 para HDTV).

### PowerVR G6230 en drm/imagination -- No soportado

El driver `drm/imagination` (merged en mainline) y el driver Vulkan PVR en Mesa
soportan estas GPUs:

| GPU | Serie | Driver Kernel | Mesa Vulkan | Estado |
|-----|-------|--------------|-------------|--------|
| AXE-1-16M | A-Series | Completo | Vulkan 1.2 | Activo |
| BXS-4-64 | B-Series | Completo | Vulkan 1.2 | Activo |
| BXM-4-64 | B-Series | Completo | Vulkan 1.2 | Activo |
| GX6250 | 6XT | Parcial | Parcial | Inactivo |
| **G6230** | **Series6** | **No** | **No** | **No listado** |

**G6230 es Series 6, NO Series 6XT.** El driver abierto se enfoca en GPUs
mas nuevas. GX6250 (la GPU 6XT mas cercana) tiene diferencias de BVNC que
requieren firmware distinto y device info especifico.

Incluso para GX6250, diferentes revisiones (p.ej. BVNC 4.45.2.58 vs 4.40.2.51)
no comparten firmware y el soporte es parcial. El blog de Imagination (Mar 2026)
confirma Zink + Mesa 26.1 funcional, pero solo para GPUs soportadas por el
driver Vulkan.

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
El firmware de Imagination disponible actualmente es para BVNCs como
4.40.2.51 (GX6250) o 36.53.104.796 (BXS-4-64). El BVNC 1.75.2.30 no tiene
firmware publico ni soporte en el driver abierto.

Se necesitaria contacto directo con Imagination para solicitar:
1. Firmware compatible con BVNC 1.75.2.30
2. Device info struct para kernel driver + Mesa
3. Confirmacion de que el driver soporta revision tan temprana de Rogue

### Tabla GIC (interrupciones) completa -- SPI de display/GPU/HDMI

Extraída del manual A80 v1.3.1 sección 3.13 (páginas 236-240). Los SPIs Linux
se calculan como `SPI + 32` (16 SGI + 16 PPI):

| SPI | Módulo | IRQ Linux | SPI | Módulo | IRQ Linux |
|-----|--------|-----------|-----|--------|-----------|
| 118 | LCD-0 (TCON0) | 150 | 125 | DE_FE0 | 157 |
| 119 | LCD-1 (TCON1) | 151 | 126 | DE_FE1 | 158 |
| **120** | **HDMI** | **152** | 127 | DE_BE0 | 159 |
| 121 | MIPI DSI | 153 | 128 | DE_BE1 | 160 |
| 123 | DRC 0/1 | 155 | **129** | **GPU** | **161** |
| 124 | DEU 0/1 | 156 | **130** | **GPU PWR** | **162** |
| **148** | **DE_BE2** | **180** | **149** | **DE_FE2** | **181** |
| 150 | eDP | 182 | | | |

Notas:
- HDMI tiene **interrupción SPI propia** (120/IRQ 152), confirmando que el
  bloque HDMI tiene lógica de control más allá de TCON1.
- GPU tiene **dos** interrupciones: GPU (129/161) + GPU PWR (130/162).
- Tercer pipe display confirmado: DE_FE2 (149/181) + DE_BE2 (148/180).
- eDP (150/182) presente en el SoC pero no declarado en DTS.
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
Interrupción `GPU PWR` (SPI 130) proviene de este módulo cuando hay power
events.

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

### Resumen de soporte upstream

- Mesa documenta un driver PowerVR abierto orientado a Vulkan para GPUs Rogue.
- El soporte activo actual esta centrado en GPUs Imagination mas nuevas o
  concretas como AXE/BXM/BXS.
- Mesa lista GX6250 como soporte parcial, pero G6230 no aparece como objetivo
  activo documentado.
- Imagination indica que el driver abierto puede correr OpenGL/OpenGL ES via
  Zink, pero eso presupone tener Vulkan funcionando.
- OpenCL no queda cubierto por ese camino; para G6230 lo mas realista es buscar
  blobs vendor.
- **Display/KMS mainline**: confirmado funcional para VGA. HDMI requiere driver
  nuevo (no compatible con sun4i-hdmi existente).
- **GPU Control Module (GCM)** documentado en manual (0x01C08000): power gating
  "Rascal/Dust" (clusters), idle status, modo HW/SW.
- **3 pipes display**: DEFE0/1/2 + DEBE0/1/2 confirmados, DTS actual solo
  declara 2.
- **G2D Mixer Processor** (0x03F00000): acelerador 2D util incluso sin GPU 3D.

Conclusion de factibilidad:

- **OpenGL acelerado mainline**: incierto/bajo, salvo que aparezca soporte PVR
  compatible con G6230 y firmware usable.
- **OpenCL mainline**: muy improbable por ahora.
- **OpenGL ES/OpenCL con blobs vendor**: posible en teoria, pero probablemente
  atado a kernel/vendor stack viejo (`linux-3.4`, Android o Linaro 2015).
- **Display/KMS mainline**: es el primer objetivo practico y medible (VGA
  funcional, HDMI requiere driver nuevo).
- **G2D acceleration**: posible via Mixer Processor incluso sin GPU 3D.

## Plan recomendado

Antes de implementar, juntar evidencia. El objetivo inicial es contestar:

- Si el display engine Allwinner puede entregar VGA con el kernel actual (HDMI
  requiere investigar/nodear primero).
- Si existe un nodo/driver viable para PowerVR G6230 en el kernel actual
  (driver abierto: no; driver vendor: requiere port desde kernel 3.4).
- Si las imagenes vendor traen blobs PowerVR utiles y para que version de
  kernel/userspace fueron hechos.
- Si OpenGL/OpenGL ES/OpenCL requieren volver a un stack legacy.
- Cual es el BVNC de G6230, para evaluar viabilidad de driver abierto.

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

#### HDMI (investigacion completa -- driver nuevo necesario)

No hay nodo HDMI en el DTS actual. Investigación del manual v1.3.1 concluye:

**El A80 NO usa un controller HDMI tipo A31.** Tiene:
- TCON1 genera timing HDTV directamente (sin MAC HDMI separada)
- PHY analógico integrado con 1 par TMDS (HTX0N/HTX0P) + HPD + DDC (HSCL/HSDA
  via GPIO PH19/PH20) + CEC (PH21)
- SPI propio (120/IRQ 152) para el bloque HDMI
- Sin capítulo dedicado en el manual, sin registros de PHY documentados
- VDD_SYS power domain (bit de hold en VDD_SYS_PWROFF_GATING_REG)

**Driver sun4i-hdmi NO compatible.** Habría que escribir driver nuevo para:
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

### Fase 4 - Inventario de blobs vendor PowerVR

Objetivo: revisar imagenes vendor/Linaro en busca de kernel modules y librerias
PowerVR.

Buscar en imagenes extraidas:

```sh
find /private/tmp/cb4-analysis -iname '*pvr*' -o -iname '*rogue*' -o -iname '*img*'
find /private/tmp/cb4-analysis -iname 'libEGL*' -o -iname 'libGLES*' -o -iname 'libOpenCL*'
find /private/tmp/cb4-analysis -iname 'pvrsrvctl' -o -iname 'pvr*'
find /private/tmp/cb4-analysis -iname '*.ko' | grep -Ei 'pvr|gpu|rogue|img'
```

Archivos a identificar:

- Kernel module PowerVR (`pvrsrvkm.ko` u otro nombre similar).
- Firmware PowerVR, si existe separado.
- `libEGL.so`, `libGLESv1_CM.so`, `libGLESv2.so`.
- `libOpenCL.so`.
- Utilidades `pvrsrvctl`, `pvrdebug`, `eglinfo`, demos o tests.

Riesgo principal:

- Si el modulo PowerVR vendor fue compilado para kernel 3.4, no va a cargar en
  kernel 6.1 sin port pesado.
- Las librerias userspace PowerVR suelen depender estrictamente del kernel
  module correspondiente.

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
