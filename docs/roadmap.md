# Roadmap

> This roadmap describes intended development direction, not completed functionality.

The project begins with the smallest useful system and adds complexity only after each lower-level layer has been validated.

## Phase 1 - Two-Camera USB Appliance

Goal:

> The Raspberry Pi 5 appears to the host as one USB webcam while two physical cameras can be selected and adjusted using GPIO controls.

### Bring-Up

- [ ] Install Raspberry Pi OS Lite 64-bit
- [ ] Validate headless SSH administration
- [ ] Validate setup utility on Pi 5
- [ ] Validate USB peripheral/device mode
- [ ] Validate `uvc-gadget` build
- [ ] Validate host UVC enumeration
- [ ] Validate UVC test pattern

### Cameras

- [ ] Detect CAM1
- [ ] Detect CAM2
- [ ] Validate persistent camera identities
- [ ] Document tested webcam models
- [ ] Validate CAM1 passthrough
- [ ] Validate CAM2 passthrough

### Physical Controls

- [ ] Validate CAM1 button
- [ ] Validate CAM2 button
- [ ] Validate focus encoder
- [ ] Validate zoom encoder
- [ ] Validate active-camera control behavior

### State

- [ ] Persist active camera
- [ ] Persist CAM1 focus/zoom
- [ ] Persist CAM2 focus/zoom
- [ ] Restore camera settings at boot
- [ ] Debounce configuration writes

### Video Output

- [ ] Improve camera switching without host disruption
- [ ] Add MJPEG UVC output
- [ ] Evaluate 720p30
- [ ] Evaluate 1080p30
- [ ] Measure latency
- [ ] Measure CPU load
- [ ] Measure USB bandwidth

## Phase 2 - OBS Video Composition

Goal:

> Add a headless compositor while keeping the same physical-control and host-output model.

- [ ] Install OBS on Pi 5
- [ ] Run OBS automatically without normal desktop use
- [ ] Configure OBS WebSocket
- [ ] Control scenes from Python
- [ ] Create CAM1 full-screen scene
- [ ] Create CAM2 full-screen scene
- [ ] Create picture-in-picture scene
- [ ] Create split-screen scene
- [ ] Feed OBS program output into USB UVC pipeline
- [ ] Remove UVC-stream restart requirement for normal camera switching

## Phase 3 - Four Cameras

- [ ] Add CAM3
- [ ] Add CAM4
- [ ] Evaluate powered USB hub
- [ ] Measure aggregate camera bandwidth
- [ ] Add physical selection controls
- [ ] Add per-camera focus/zoom state
- [ ] Validate simultaneous camera availability in OBS

## Phase 4 - Network Sources

- [ ] Add SRT input support
- [ ] Stream Raspberry Pi 4 desktop to Pi 5
- [ ] Keep Pi 4 local monitor active while streaming
- [ ] Add desktop full-screen scene
- [ ] Add desktop + active camera PIP
- [ ] Add desktop + camera split-screen
- [ ] Document latency and network requirements

## Phase 5 - Operator Display

Use the Pi 5 second HDMI output for an operator/confidence display.

- [ ] Active camera indicator
- [ ] Program preview
- [ ] Focus value
- [ ] Zoom value
- [ ] Autofocus state
- [ ] Camera online/offline status
- [ ] OBS status
- [ ] SRT status
- [ ] USB output status
- [ ] CPU temperature/load
- [ ] Recent control events

Operator information should never appear in the clean program feed.

## Phase 6 - Optional HDMI Output

USB UVC remains the core output.

HDMI becomes an optional alternative or expansion:

```text
Pi 5 -> HDMI -> USB 3 capture device -> host
```

Goals:

- [ ] Clean dedicated HDMI program output
- [ ] Validate USB 3 capture device
- [ ] Compare latency against native UVC gadget output
- [ ] Compare 1080p performance
- [ ] Document fallback/redundancy workflow

## Phase 7 - USB Control Surfaces

The GPIO controller remains the baseline reference implementation.

Optional USB devices may supplement or replace it.

Potential TreasLin N3 mapping:

```text
LCD 1  CAM1
LCD 2  CAM2
LCD 3  CAM3
LCD 4  CAM4
LCD 5  DESKTOP
LCD 6  COMPOSITE

Knob 1 FOCUS
Knob 2 ZOOM
Knob 3 EXPOSURE / MODE
```

Goals:

- [ ] Detect supported N3 hardware revision
- [ ] Validate Linux input/output support
- [ ] Map buttons to controller actions
- [ ] Map rotary encoders
- [ ] Update LCD keys with active state
- [ ] Keep control logic hardware-independent

## Longer-Term Ideas

Possible future work:

- scene profiles
- camera labels
- web configuration UI
- configuration export/import
- automatic camera capability discovery
- digital zoom through OBS
- camera health monitoring
- recording
- streaming to additional destinations
- remote control API
- software-defined button layouts
- packaged image or automated installer
