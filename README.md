# Pi Video Switcher

> **Development status: pre-alpha / untested**
>
> This repository is at the initial hardware and software bring-up stage. The v0.1 setup script has been written, but the complete system has **not yet been tested on Raspberry Pi 5 hardware**. USB UVC output, camera switching, GPIO controls, focus/zoom control, and the generated systemd services should all be considered experimental until validated.

Pi Video Switcher is an open-source Raspberry Pi 5 project for building a headless, physically controlled multi-camera video appliance.

The initial goal is intentionally small: connect two USB cameras to a Raspberry Pi 5, select the active camera with physical buttons, adjust focus and zoom with rotary encoders, and present the Pi itself to a host computer as a USB UVC camera.

Longer term, the project is intended to grow into a modular video production controller with OBS-based compositing, additional cameras and network video sources, an operator display, and optional control/output hardware.

## Project Goals

The project is being designed around four independent layers:

1. **Video sources** - USB cameras initially, with network and media sources planned.
2. **Physical controls** - GPIO buttons and rotary encoders initially, with optional USB controllers planned.
3. **Video processing** - direct camera passthrough first, with OBS compositing planned.
4. **Outputs** - USB UVC as the core output, with HDMI as an optional expansion path.

The intent is to avoid tying the project to one specific controller, camera, or output device.

## v0.1 Scope

The first software release targets:

- Raspberry Pi 5
- Raspberry Pi OS Lite 64-bit
- Headless operation
- Two USB UVC/V4L2 cameras
- Two GPIO camera-select buttons
- One rotary encoder for focus
- One rotary encoder for zoom
- USB UVC gadget output over the Pi 5 USB-C device port
- Text-based setup and configuration menu
- systemd-managed runtime services
- Persistent configuration
- Live logging through `journalctl`
- Basic switching between Camera 1 and Camera 2

OBS is **not part of v0.1**. The first milestone is proving the lower-level camera, GPIO, V4L2, and USB gadget pipeline before introducing a compositor.

## Current Validation Status

At the time of this initial release:

| Component | Status |
| --- | --- |
| Setup/configuration script | Written |
| Raspberry Pi 5 installation | **Not yet tested** |
| GPIO button handling | **Not yet hardware tested** |
| Rotary encoder handling | **Not yet hardware tested** |
| V4L2 focus control | **Not yet tested with target cameras** |
| V4L2 zoom control | **Not yet tested with target cameras** |
| USB gadget enumeration | **Not yet tested** |
| UVC test-pattern output | **Not yet tested** |
| Camera 1 passthrough | **Not yet tested** |
| Camera 2 passthrough | **Not yet tested** |
| Camera switching while attached to host | **Not yet tested** |
| OBS integration | Planned |
| HDMI output | Planned optional expansion |
| Network/SRT sources | Planned |
| USB control surface support | Planned |

Expect changes as hardware testing begins.

Issues and pull requests are welcome, but do not treat the current code as production-ready.

## Initial Architecture

```text
 USB Camera 1 ----\
                   \
                    +---- Raspberry Pi 5 ---- USB-C UVC ---- Host PC
                   /             ^
 USB Camera 2 ----/              |
                                 |
                       GPIO Camera Controller
                         |              |
                    CAM1 / CAM2     Focus / Zoom
                      buttons         encoders
```

The host computer should eventually see a single camera device regardless of which physical camera is active.

The Pi is intended to operate without a keyboard, mouse, or desktop environment once configured.

## Planned Architecture

Later releases are intended to evolve toward:

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
                    +-----------+-----------+
                    |                       |
                 USB UVC                  HDMI
                    |                       |
                 Host PC            Optional Capture
                    |
                  Zoom
                 Teams
                  etc.

                         CONTROL INPUTS
                                |
                  +-------------+-------------+
                  |                           |
             GPIO Controls             USB Controller
          buttons + encoders             planned
```

OBS will eventually provide:

- full-screen camera scenes
- picture-in-picture
- split-screen layouts
- camera plus desktop/demo layouts
- network video sources
- reusable scene compositions

The underlying control interface is intended to remain independent of OBS so GPIO controls can later be supplemented or replaced without rewriting the camera-control logic.

## Hardware for v0.1

Minimum planned hardware:

- Raspberry Pi 5
- Appropriate Raspberry Pi 5 cooling
- Separate safe 5V power solution while USB-C is being used in device/gadget mode
- Two USB webcams
- Powered USB hub recommended for multi-camera use
- Two momentary pushbuttons
- Two rotary encoders
- Breadboard and jumper wires
- USB data cable between the Pi 5 USB-C device port and host computer

### Webcam Requirements

Linux camera controls vary significantly between webcam models.

For the best results, cameras should expose standard V4L2 controls such as:

```text
focus_absolute
focus_auto
zoom_absolute
```

A camera may work for video while lacking manual focus or hardware zoom.

The setup utility includes options to inspect both supported video formats and available controls before configuring the controller.

## Default GPIO Layout

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

The GPIO assignments are configurable through the setup menu.

### Button Wiring

The current software uses the Raspberry Pi's internal pull-up resistors.

Conceptually:

```text
GPIO5 ---- Camera 1 button ---- GND
GPIO6 ---- Camera 2 button ---- GND
```

### Encoder Wiring

Focus:

```text
Encoder A ---- GPIO17
Encoder B ---- GPIO27
Common ------- GND
```

Zoom:

```text
Encoder A ---- GPIO22
Encoder B ---- GPIO23
Common ------- GND
```

See the hardware documentation and breadboard layout before connecting components.

> Raspberry Pi GPIO uses 3.3V logic. Do not apply 5V directly to a GPIO input.

## Important Pi 5 USB-C Power Consideration

The Raspberry Pi 5 USB-C connector is normally used for power, but this project initially intends to use it as the USB device/gadget connection to the host computer.

That means power must be handled separately and safely.

Do not improvise a second power feed or connect power sources together without understanding the electrical path. The final recommended power arrangement will be documented after the first hardware configuration is tested.

USB gadget mode should be treated as experimental in this repository until the hardware path has been validated.

## Software

The current setup utility is:

```text
scripts/pi-camera-controller-setup.sh
```

It is intended to configure and manage the first prototype without requiring manual editing of multiple system files.

### Menu Capabilities

The current script provides menu options for:

- displaying project and service status
- first-pass setup
- installing required packages
- detecting V4L2 cameras
- assigning Camera 1 and Camera 2
- inspecting camera video formats
- inspecting focus and zoom controls
- configuring GPIO pins
- live-testing buttons and encoders
- installing runtime files
- starting and stopping the controller service
- configuring Pi 5 USB peripheral mode
- checking USB gadget status
- building the upstream `uvc-gadget` userspace utility
- starting a USB test-pattern stream
- starting active-camera USB passthrough
- stopping USB video
- following live logs
- displaying the raw JSON configuration
- switching the Pi to headless boot
- rebooting

## Configuration

Persistent configuration is stored at:

```text
/etc/pi-camera-controller/config.json
```

The initial configuration includes:

- Camera 1 device
- Camera 2 device
- button GPIO assignments
- focus encoder GPIO assignments
- zoom encoder GPIO assignments
- V4L2 focus control name
- V4L2 zoom control name
- focus increment
- zoom increment
- USB product name
- USB video resolution
- USB frame rate
- USB source mode

The current prototype prefers persistent Linux device paths under:

```text
/dev/v4l/by-id/
```

when available rather than depending on `/dev/video0`, `/dev/video1`, and similar numbers that may change between boots.

## Runtime State

The v0.1 controller currently maintains the active camera as runtime state.

Per-camera focus and zoom persistence across reboots is **planned but not implemented in this initial script**.

A future release is intended to retain separate focus and zoom settings for each configured camera and restore them at startup.

## Installation

### 1. Install Raspberry Pi OS

The initial target is:

**Raspberry Pi OS Lite 64-bit**

Configure SSH and networking during imaging so the Pi can be administered remotely.

### 2. Clone the repository

```bash
git clone https://github.com/ericburnsonline/pi-video-switcher.git
cd pi-video-switcher
```

### 3. Make the setup script executable

```bash
chmod +x scripts/pi-camera-controller-setup.sh
```

### 4. Run it as your normal user

```bash
./scripts/pi-camera-controller-setup.sh
```

The utility calls `sudo` internally when privileged changes are required. Running the entire menu with `sudo` should not normally be necessary.

### 5. Run First-Pass Setup

From the menu:

```text
2) First-pass setup
```

This is intended to:

- install required packages
- create the default configuration
- install controller runtime files
- configure USB peripheral mode
- build the UVC gadget userspace application

A reboot is required after enabling USB peripheral mode.

### 6. Assign Cameras

After reboot:

```text
4) Detect/list cameras
5) Assign CAM1 or CAM2
6) Inspect camera formats + focus/zoom controls
```

Verify both cameras are detected and inspect their capabilities before assuming manual focus or zoom is available.

### 7. Test the Controls

Before involving USB video:

```text
8) Live-test buttons + rotary encoders
```

Expected behavior:

```text
BUTTON 1 -> CAM1
BUTTON 2 -> CAM2
FOCUS +
FOCUS -
ZOOM +
ZOOM -
```

### 8. Prove USB with a Test Pattern

The first USB video test should use:

```text
15) Start USB TEST PATTERN
```

The host computer should eventually enumerate a UVC camera called:

```text
Pi Camera Controller
```

Do not move on to real-camera passthrough until the basic USB test pattern is working.

### 9. Test Camera Passthrough

After USB gadget enumeration has been proven:

```text
16) Start USB ACTIVE CAMERA passthrough
```

The initial USB profile advertises a deliberately conservative:

```text
640 x 360
YUYV
30 fps
```

This is intended for bring-up and troubleshooting, not as the final project video format.

Compressed MJPEG and higher resolutions are planned once the USB pipeline has been validated.

## Logging and Troubleshooting

The project installs a convenience command:

```bash
camera-log
```

This follows the logs for:

```text
pi-camera-controller.service
pi-camera-uvc-gadget.service
pi-camera-uvc.service
```

Individual service logs can also be viewed directly:

```bash
journalctl -u pi-camera-controller.service
journalctl -u pi-camera-uvc-gadget.service
journalctl -u pi-camera-uvc.service
```

Useful hardware troubleshooting commands include:

```bash
v4l2-ctl --list-devices
lsusb
ls /sys/class/udc
```

To inspect a camera:

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
v4l2-ctl -d /dev/video0 --list-ctrls
```

The actual persistent camera path configured by the project may differ from `/dev/video0`.

## Intended v0.1 Test Sequence

Hardware testing should proceed in small checkpoints:

```text
1. Pi boots headless
2. SSH works
3. Both cameras enumerate
4. Camera formats and controls can be queried
5. CAM1/CAM2 buttons register
6. Focus encoder registers
7. Zoom encoder registers
8. USB gadget controller is visible
9. Host PC enumerates Pi Camera Controller
10. Host receives UVC test pattern
11. Host receives Camera 1
12. Host receives Camera 2
13. Camera selection works
14. Focus control works on selected camera
15. Zoom control works on selected camera
```

Failures should be documented before moving to the next layer.

## Roadmap

### Phase 1 - USB Camera Appliance

- [ ] Validate setup script on Raspberry Pi 5
- [ ] Validate two-camera discovery
- [ ] Validate GPIO camera buttons
- [ ] Validate focus encoder
- [ ] Validate zoom encoder
- [ ] Validate USB UVC gadget enumeration
- [ ] Validate USB test pattern
- [ ] Validate Camera 1 passthrough
- [ ] Validate Camera 2 passthrough
- [ ] Improve live camera switching
- [ ] Add per-camera persistent focus and zoom state
- [ ] Add compressed MJPEG output
- [ ] Evaluate 720p30
- [ ] Evaluate 1080p30

### Phase 2 - OBS Composition

- [ ] Install and run OBS headlessly
- [ ] Add full-screen camera scenes
- [ ] Add picture-in-picture scenes
- [ ] Add split-screen scenes
- [ ] Control OBS through WebSocket
- [ ] Route OBS program video into USB UVC output

### Phase 3 - Expanded Sources

- [ ] Expand to four USB cameras
- [ ] Add SRT network video sources
- [ ] Add Raspberry Pi desktop capture source
- [ ] Support mixed camera and desktop compositions

### Phase 4 - Operator Interface

- [ ] Add second HDMI operator display
- [ ] Show active camera
- [ ] Show focus and zoom values
- [ ] Show camera availability
- [ ] Show video/OBS status
- [ ] Show system health

### Phase 5 - Optional Expansion Hardware

- [ ] HDMI program output
- [ ] USB HDMI capture workflow
- [ ] USB control-surface support
- [ ] TreasLin N3 experimentation

USB UVC remains the intended core output. HDMI is planned as an optional higher-bandwidth or compatibility path rather than a requirement.

## Known Limitations

This initial release has several intentional limitations:

- Nothing has been validated on the target Raspberry Pi 5 yet.
- The UVC configuration starts at low-resolution uncompressed video.
- Camera switching currently relies on restarting the userspace UVC streamer.
- Focus and zoom depend on controls exposed by each webcam.
- Focus and zoom values are not yet persisted by the controller.
- Active camera runtime state is not intended as durable configuration.
- OBS integration does not yet exist.
- No four-camera testing has been performed.
- No automated test suite exists yet.
- USB-C gadget-mode power handling still requires hardware validation and documentation.

## Why Build This?

Typical USB webcams are individually simple, but multi-camera presentation workflows quickly become dependent on software interfaces, keyboard shortcuts, capture devices, and manually arranged windows.

This project explores whether a Raspberry Pi can act as a dedicated video appliance that hides that complexity from the conferencing computer.

The desired end-user experience is:

```text
Select camera.
Turn focus or zoom control.
Use composed layouts when needed.
Host computer sees one camera.
```

The host does not need to know how many physical or network video sources are behind that one output.

## Contributing

The project is still in initial bring-up, so interfaces and configuration formats may change.

Hardware test results are especially useful. When reporting an issue, include where possible:

- Raspberry Pi model
- Raspberry Pi OS version
- kernel version
- webcam make/model
- `v4l2-ctl --list-formats-ext` output
- `v4l2-ctl --list-ctrls` output
- relevant `camera-log` output
- whether the problem occurs before or after USB gadget enumeration

## License

Licensed under the Apache License 2.0.

See `LICENSE` for details.
