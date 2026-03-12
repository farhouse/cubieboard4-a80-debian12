# Cubieboard4 A80 — Ficha de hardware y acceso serial

> Completar/validar en la primera sesión física con la placa.

## Identificación de placa

- Modelo: **Cubieboard4 (Allwinner A80)**
- SoC: Allwinner A80
- RAM: _(completar)_
- Storage principal: _(eMMC / microSD / ambos, completar)_
- Estado físico / observaciones: _(completar)_

## Alimentación

- Fuente usada: _(voltaje / amperaje)_
- Conector: _(completar)_
- Comportamiento al energizar: _(LEDs, consumo, señales de vida)_
- Riesgos detectados: _(reinicios, caída de tensión, temperatura)_

## Acceso serial UART

- Adaptador USB-TTL: _(modelo/chipset)_
- Puerto host (ej. `/dev/tty.usbserial-*`): _(completar)_
- Config habitual:
  - Baud: **115200**
  - Data bits: **8**
  - Parity: **N**
  - Stop bits: **1**
  - Flow control: **none**

### Pinout (validar antes de conectar)

- GND ↔ GND
- TX (adaptador) ↔ RX (placa)
- RX (adaptador) ↔ TX (placa)

> ⚠️ No conectar VCC del adaptador TTL si la placa ya está alimentada externamente.

## Comandos útiles (host macOS/Linux)

### Detectar puerto serial

```bash
ls /dev/tty.*
```

### Abrir consola con `screen`

```bash
screen /dev/tty.usbserial-XXXX 115200
```

Salir de `screen`:
1. `Ctrl + A`
2. `K`
3. Confirmar `y`

### Abrir consola con `picocom` (si está instalado)

```bash
picocom -b 115200 /dev/tty.usbserial-XXXX
```

## Checklist de primera validación

- [ ] La consola serial abre correctamente
- [ ] Se ve output de boot al energizar
- [ ] Se identifica etapa de bootloader (U-Boot u otro)
- [ ] Se registra log inicial en `logs/`
- [ ] Se documenta resultado en `notes/`

## Referencias / links

- _(agregar links confiables de pinout/datasheet/manual)_
