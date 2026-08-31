# Architecture

> **Status: design document for an untested pre-alpha implementation**

Pi Video Switcher is intended to behave like a dedicated video appliance rather than a general-purpose Raspberry Pi desktop.

The design separates four concerns:

1. video sources
2. physical control inputs
3. video switching/compositing
4. output transports

Keeping those layers separate should allow the project to grow without tying the controller to one camera model, one control surface, or one output method.

## v0.1 Architecture

The first milestone deliberately avoids OBS.

```text
 USB Camera 1 ----\
                   \
                    +---- V4L2 ---- Controller ---- UVC Gadget ---- USB-C ---- Host PC
                   /                    ^
 USB Camera 2 ----/                     |
                                        |
                               GPIO physical controls
                                  |            |
                             CAM1 / CAM2   Focus / Zoom
                               buttons      encoders
```

The host computer should eventually see one UVC camera:

```text
Pi Camera Controller
```

The Pi handles which physical camera supplies that output.

## Why Start Without OBS?

The initial build needs to prove several lower-level functions:

- Pi 5 USB device mode
- UVC enumeration
- userspace frame delivery
- camera discovery
- V4L2 controls
- GPIO inputs
- camera selection
- systemd startup
- headless logging

Introducing OBS before those are working would make troubleshooting more difficult.

OBS is planned only after the basic transport and controls are proven.

## Control Abstraction

The controller should operate on actions rather than specific pieces of hardware.

Conceptually:

```text
GPIO Button 1 ----\
                   +---- select_camera(1)
Future N3 key ----/
```

Similarly:

```text
GPIO encoder ----\
                  +---- adjust_focus(+1)
Future knob  -----/
```

This makes GPIO the first control implementation rather than the permanent definition of the interface.

## Camera Identity

Linux `/dev/videoN` assignments may change between boots.

The design therefore prefers persistent paths such as:

```text
/dev/v4l/by-id/...
```

when the camera exposes them.

Logical camera identity should remain:

```text
CAM1
CAM2
CAM3
CAM4
```

regardless of the underlying device node.

## Per-Camera State

Each physical camera should eventually maintain its own state, including:

```text
focus
zoom
autofocus
exposure
```

The intended behavior is:

```text
Select CAM1
Adjust focus and zoom

Select CAM2
Adjust different focus and zoom

Return to CAM1
Restore/use CAM1 settings
```

The current v0.1 script does **not yet persist focus and zoom across reboot**.

That is planned for an early revision.

## Planned OBS Architecture

Once the lower-level system is reliable:

```text
                         VIDEO SOURCES
                               |
              +----------------+----------------+
              |                |                |
         USB Cameras       SRT Sources        Media
              |                |                |
              +----------------+----------------+
                               |
                              OBS
                               |
                    Program/composite output
                               |
                  +------------+------------+
                  |                         |
             USB UVC                    HDMI output
                  |                         |
              Host PC                 Optional path
```

OBS becomes the compositor, not the controller.

The Python controller can communicate with OBS through WebSocket while still managing camera-specific V4L2 controls directly.

## Planned Scene Types

Examples include:

```text
CAM1_FULL
CAM2_FULL
CAM3_FULL
CAM4_FULL

CAM1_CAM2_SPLIT
CAM1_CAM2_PIP

DESKTOP_FULL
DESKTOP_CAM_PIP
DESKTOP_CAM_SPLIT
```

## Network Video Sources

A future Raspberry Pi 4 or other computer may transmit a desktop or video feed over the network using SRT.

Conceptually:

```text
Pi 4 desktop
    |
screen capture / encode
    |
SRT
    |
network
    |
OBS on Pi 5
```

The Pi 4 can continue displaying its normal local desktop while simultaneously streaming that desktop to the Pi 5.

## Operator Display

A future second HDMI output may provide an operator interface separate from the program feed.

Possible information:

```text
Active Camera: CAM2
Focus: 148
Zoom: 120
Autofocus: Off

CAM1: OK
CAM2: OK
CAM3: OK
CAM4: OK

OBS: Connected
SRT: Connected
USB output: Active

CPU: 32%
Temperature: 58 C
```

This operator information must not appear in the clean program output.

## Output Philosophy

USB UVC is the intended core output because it allows the Pi itself to appear as a camera to conferencing software.

HDMI is planned as an optional expansion path.

This provides two possible modes:

```text
Core:
Pi -> USB UVC -> host

Expansion:
Pi -> HDMI -> capture device -> host
```

The HDMI path may be useful for higher-bandwidth output, compatibility, or redundancy without replacing the USB-first architecture.
