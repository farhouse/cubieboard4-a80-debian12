# Acto 2 - GPU, OpenGL y OpenCL en Cubieboard4 A80

Fecha: 2026-05-22

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

## Lectura de soporte upstream

El soporte abierto moderno de PowerVR existe, pero no se puede asumir que sirva
directamente para esta placa.

- Mesa documenta un driver PowerVR abierto orientado a Vulkan para GPUs Rogue.
- El soporte activo actual esta centrado en GPUs Imagination mas nuevas o
  concretas como AXE/BXM/BXS.
- Mesa lista GX6250 como soporte parcial, pero G6230 no aparece como objetivo
  activo documentado.
- Imagination indica que el driver abierto puede correr OpenGL/OpenGL ES via
  Zink, pero eso presupone tener Vulkan funcionando.
- OpenCL no queda cubierto por ese camino; para G6230 lo mas realista es buscar
  blobs vendor.

Conclusion de factibilidad:

- **OpenGL acelerado mainline**: incierto/bajo, salvo que aparezca soporte PVR
  compatible con G6230 y firmware usable.
- **OpenCL mainline**: muy improbable por ahora.
- **OpenGL ES/OpenCL con blobs vendor**: posible en teoria, pero probablemente
  atado a kernel/vendor stack viejo (`linux-3.4`, Android o Linaro 2015).
- **Display/KMS mainline**: es el primer objetivo practico y medible.

## Plan recomendado

Antes de implementar, juntar evidencia. El objetivo inicial es contestar:

- Si el display engine Allwinner puede entregar VGA/HDMI con el kernel actual.
- Si existe un nodo/driver viable para PowerVR G6230 en el kernel actual.
- Si las imagenes vendor traen blobs PowerVR utiles y para que version de
  kernel/userspace fueron hechos.
- Si OpenGL/OpenGL ES/OpenCL requieren volver a un stack legacy.

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

Objetivo: validar VGA primero, porque el DTS actual ya define `vga-connector`,
`vga-dac` y `tcon0`.

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
- linux-sunxi A80:
  https://linux-sunxi.org/A80
