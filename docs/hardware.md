# Hardware

> **Status: untested initial hardware design**
>
> This document describes the planned v0.1 breadboard configuration. It has not yet been validated on the target Raspberry Pi 5 hardware.

## v0.1 Hardware

The initial prototype is designed around:

- Raspberry Pi 5
- Appropriate Raspberry Pi 5 cooling
- Two USB UVC/V4L2 webcams
- Powered USB hub recommended for multi-camera use
- Two momentary pushbuttons
- Two rotary encoders
- Breadboard and jumper wires
- USB data cable from the Pi 5 USB-C device port to the host computer
- A safe separate power method for the Pi while USB-C is used in device/gadget mode

## GPIO Numbering

The software uses **BCM GPIO numbering**, not physical header pin numbers.

| Function | BCM GPIO | Physical Pin |
| --- | ---: | ---: |
| Camera 1 button | GPIO 5 | 29 |
| Camera 2 button | GPIO 6 | 31 |
| Focus encoder A | GPIO 17 | 11 |
| Focus encoder B | GPIO 27 | 13 |
| Zoom encoder A | GPIO 22 | 15 |
| Zoom encoder B | GPIO 23 | 16 |
| Ground | GND | Any appropriate GND pin |

Run this on Raspberry Pi OS for a local header reference:

```bash
pinout
```

## Button Wiring

The v0.1 controller uses the Raspberry Pi's internal pull-up resistors.

Conceptually:

```text
GPIO5 ---- Camera 1 button ---- GND
GPIO6 ---- Camera 2 button ---- GND
```

No external pull-up resistor is intended for the initial prototype.

## Rotary Encoder Wiring

Focus encoder:

```text
Encoder A ---- GPIO17
Encoder B ---- GPIO27
Common ------- GND
```

Zoom encoder:

```text
Encoder A ---- GPIO22
Encoder B ---- GPIO23
Common ------- GND
```

Encoder push switches are not used in v0.1.

A later version may use them for functions such as:

- focus encoder press: toggle autofocus
- zoom encoder press: reset zoom

## GPIO Voltage Warning

Raspberry Pi GPIO is **3.3V logic**.

Do not apply 5V directly to GPIO inputs.

If using a rotary encoder module rather than a bare mechanical encoder, verify the module circuitry before connecting its power pin.

## Webcam Requirements

The video portion of a webcam may work even when manual focus or zoom controls are unavailable.

The project is most useful with cameras exposing standard V4L2 controls such as:

```text
focus_absolute
focus_auto
zoom_absolute
```

Inspect a camera with:

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
v4l2-ctl -d /dev/video0 --list-ctrls
```

The setup utility prefers persistent device paths under:

```text
/dev/v4l/by-id/
```

when available.

## USB Hub

A powered USB hub is recommended once multiple cameras are connected.

The initial two-camera prototype may work with direct Pi USB connections depending on the cameras' power draw and video formats, but the design should not assume that four future cameras can be reliably powered from the Pi.

Bandwidth should also be considered separately from power.

Compressed camera formats such as MJPEG may substantially reduce USB bandwidth compared with uncompressed formats.

## Pi 5 USB-C Device Mode

The project's initial output path is:

```text
Camera(s)
   |
Raspberry Pi 5
   |
USB UVC gadget
   |
Pi 5 USB-C
   |
Host PC
```

The Pi 5 USB-C connector is normally also used for power.

Because this project intends to use that connector for USB device/gadget mode, the Pi must have a separate, safe power arrangement.

The final recommended power arrangement is intentionally **not documented as settled yet** because it still requires hardware validation.

## Planned Expansion Hardware

Later phases may add:

- four total USB cameras
- second HDMI operator/status display
- optional HDMI program output
- optional USB HDMI capture device
- optional USB control surface such as the TreasLin N3
- additional network video sources
