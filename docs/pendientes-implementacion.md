# Pendientes de implementacion y validacion

Ultima actualizacion: 2026-07-13

Este es el unico backlog activo del proyecto. `docs/estado-validado.md` resume
lo ya logrado y `notes/` conserva la historia de investigacion. No mover aqui
trabajos ya cerrados.

## P0 - Proteger la reproducibilidad

### Validar el builder `a5e9a48` en Linux y hardware

La implementacion soporta ejecucion desde un clon y ejecucion remota, descarga
scripts auxiliares faltantes y verifica sus SHA256. Las SD creadas con
versiones anteriores funcionaron, pero esta version aun no se probo completa.

Validar:

1. Construccion con el perfil `Recommended` desde un clon limpio.
2. Construccion con el comando remoto documentado en `README.md`.
3. Escritura a una microSD limpia y boot automatico hasta login.
4. Presencia del DTB, U-Boot corregido, firmware AP6330, helpers y hooks de
   kernel en el rootfs resultante.
5. WiFi end-to-end en la imagen recien construida.

Criterio de cierre: ambas rutas producen una imagen verificada que arranca en
la Cubieboard4. Registrar comandos, versiones de herramientas, SHA256 final,
tabla de particiones, UUID, commit usado y log serial.

### Validar mantenimiento de `boot.scr` tras cambios de kernel

Los hooks `scripts/regenerate-bootscr-hook` y
`scripts/regenerate-bootscr-rmhook` corrigen la causa que rompio el boot al
actualizar el kernel, pero todavia no fueron validados en hardware.

Validar primero desde microSD:

1. Instalar o actualizar un kernel y comprobar que `boot.cmd` y `boot.scr`
   apuntan al nuevo `vmlinuz` e `initrd`.
2. Reiniciar y verificar el kernel activo con `uname -r`.
3. Eliminar el kernel anterior, ejecutar el flujo normal de autoremove si
   corresponde y comprobar el hook `postrm`.
4. Reiniciar nuevamente.
5. Repetir en eMMC cuando la prueba SD quede cerrada.

Criterio de cierre: boot correcto despues de la instalacion y despues de la
remocion de kernels, tanto en SD como en eMMC, con log y contenido de
`boot.cmd`/`boot.scr` registrado en cada etapa.

## P1 - Regresiones y red cableada

### Validar la revision actual del instalador eMMC

La instalacion Debian 12 a eMMC ya funciono. Falta una regresion acotada de los
cambios posteriores: deteccion de medios, preservacion del wizard WiFi e
instalacion de los hooks vecinos.

Criterio de cierre: `--dry-run` identifica correctamente origen y destino, y
una ejecucion controlada confirma que el sistema eMMC conserva
`wifi-wizard.sh`, instala ambos hooks y sigue arrancando sin microSD.

### Resolver Ethernet

El RTL8211E negocia Gigabit Full Duplex, pero no se observaron paquetes IPv4
TX/RX. Hay que separar MAC, PHY/DTS y red externa.

Validar:

- contadores y captura ARP/DHCP con `ip -s link` y `tcpdump -eni`;
- MAC fija localmente valida frente a la MAC aleatoria;
- enlace directo con IP estatica para excluir DHCP y switch;
- mensajes `stmmac`, estado PHY y delays RGMII del DTS.

Criterio de cierre: trafico bidireccional estable con DHCP o IP estatica, o
evidencia reproducible que aisle el defecto y permita definir el cambio de
driver/DTS siguiente.

### Probar una imagen Bookworm nueva de Johan

Probar `debian-bookworm-armhf-rieco4.bin.gz` o el artefacto vigente solamente
despues de cerrar el baseline del builder, para no mezclar variables.

Criterio de cierre: registrar URL, SHA256, kernel, resultado de boot y cualquier
ajuste requerido por el builder. No reemplazar el baseline preservado hasta
que la nueva combinacion pase las mismas pruebas.

## P2 - Perifericos y upstream

### Habilitar Bluetooth AP6330

Identificar UART y GPIO de enable/reset desde FEX o fuentes vendor, instalar
`bcm40183b2.hcd` y declarar la configuracion necesaria para mainline.

Criterio de cierre: firmware cargado, `hci0` disponible, scan y conexion con un
dispositivo documentados.

### Validar VGA y estudiar HDMI

Probar primero VGA y el pipeline DRM/framebuffer ya declarado. Para HDMI,
continuar el analisis vendor antes de agregar nodos al DTB estable; mainline no
declara el bloque HDMI del A80 en el DTS actual.

Criterio de cierre: salida basica y modo detectado documentados para cada
conector, o bloqueo aislado con logs DRM/EDID y siguiente cambio concreto.

### Dar seguimiento al parche U-Boot

El parche del typo `CONFIG_MACH_SUN9I_A80` ya fue enviado a
`u-boot@lists.denx.de`, con CC a Andre Przywara, Peng Fan y Jaehoon Chung. No
hay Message-ID versionado.

Criterio de cierre: registrar enlace o Message-ID real y resultado de la
revision; si corresponde, preparar una nueva version o resend segun el feedback
upstream.

## P3 - Investigacion postergada

### GPU PowerVR G6230

No implementar cambios en el DTB estable hasta que exista una ruta tecnica
viable. El bloqueo conocido es la falta de soporte y firmware publico para
BVNC `1.75.2.30`.

Criterio de cierre de investigacion: identificar un stack kernel, firmware y
userspace compatible y redistribuible, o documentar que la aceleracion no es
alcanzable con componentes disponibles.

## Evidencia pendiente de incorporar

En la proxima prueba de hardware, guardar un boot log limpio con el DTB final y
sin payloads de transferencia. Promover tambien la correspondencia FEX a DTS a
`docs/device-tree/` cuando sea estable.

Criterio de cierre: evidencia raw en `logs/` con fecha y resumen enlazado desde
la matriz; tabla FEX a DTS con fuente y estado de validacion de cada entrada.
