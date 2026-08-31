# Installation

> **Status: pre-alpha and not yet validated end-to-end on Raspberry Pi 5**

This guide describes the intended v0.1 installation sequence.

Do not assume a step is working merely because the setup script completed. Validate each checkpoint before moving on.

## Target OS

Initial target:

```text
Raspberry Pi OS Lite 64-bit
```

During imaging, configure:

- hostname
- user account
- networking
- SSH

The intended normal management path is SSH.

## Clone the Repository

```bash
git clone https://github.com/ericburnsonline/pi-video-switcher.git
cd pi-video-switcher
```

## Make the Setup Utility Executable

```bash
chmod +x scripts/pi-camera-controller-setup.sh
```

## Start the Utility

Run it as your normal user:

```bash
./scripts/pi-camera-controller-setup.sh
```

The script uses `sudo` internally when a privileged action is required.

## First-Pass Setup

From the menu:

```text
2) First-pass setup
```

The first-pass setup is intended to:

- install required packages
- create the configuration directory
- install controller runtime files
- configure USB peripheral mode
- install systemd units
- build the upstream UVC gadget userspace application

A reboot is required after enabling USB peripheral mode.

## Checkpoint 1: Headless Access

After reboot, verify SSH still works.

Expected:

```bash
ssh <user>@<pi-hostname>
```

You should reach a shell normally.

If SSH fails, resolve networking or boot problems before continuing.

## Checkpoint 2: Detect Cameras

From the setup menu:

```text
4) Detect/list cameras
```

Or manually:

```bash
v4l2-ctl --list-devices
```

Expected:

- both webcams appear
- persistent `/dev/v4l/by-id/...` paths are shown when available

Do not continue with camera controls until both intended cameras can be identified reliably.

## Assign CAM1 and CAM2

From the menu:

```text
5) Assign CAM1 or CAM2
```

Assign each logical camera to the desired persistent device path.

## Checkpoint 3: Inspect Video Formats

From the menu:

```text
6) Inspect camera formats + focus/zoom controls
```

Or manually:

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
```

Record useful formats and frame rates.

The first UVC proof uses a deliberately conservative output format and should not be treated as final video quality.

## Checkpoint 4: Inspect Camera Controls

Also inspect:

```bash
v4l2-ctl -d /dev/video0 --list-ctrls
```

Look for controls such as:

```text
focus_absolute
focus_auto
zoom_absolute
```

A camera that does not expose manual focus cannot be made to support it by this project.

## Checkpoint 5: Test GPIO

Wire the two buttons and two encoders according to `docs/hardware.md`.

Then use:

```text
8) Live-test buttons + rotary encoders
```

Expected events:

```text
BUTTON 1 -> CAM1
BUTTON 2 -> CAM2
FOCUS +
FOCUS -
ZOOM +
ZOOM -
```

Resolve wiring and GPIO problems before starting the permanent controller service.

## Start the Controller

From the menu:

```text
10) Start controller service
```

Then follow logs:

```bash
camera-log
```

Expected:

```text
[controller] Pi Camera Controller v0.1 started
[controller] CAM1: ...
[controller] CAM2: ...
[controller] heartbeat active=CAM1 ...
```

## Checkpoint 6: USB Device Controller

Use:

```text
13) USB gadget status
```

Or manually:

```bash
ls /sys/class/udc
```

Expected:

At least one USB Device Controller entry.

If `/sys/class/udc` is empty, do not attempt video streaming yet.

## Checkpoint 7: USB Test Pattern

Start:

```text
15) Start USB TEST PATTERN
```

Connect the Pi 5 USB-C gadget connection to the host PC.

The host should eventually enumerate a camera named approximately:

```text
Pi Camera Controller
```

Open the host operating system's camera application before involving Zoom.

Expected:

- camera device appears
- test video appears

If the device appears but video does not, the USB descriptor path is partly working and troubleshooting can focus on the userspace UVC stream.

## Checkpoint 8: Camera 1 Passthrough

Only after the test pattern works:

```text
16) Start USB ACTIVE CAMERA passthrough
```

Select CAM1.

Expected:

The host receives CAM1 video.

## Checkpoint 9: Camera 2 Passthrough

Press the CAM2 button.

Expected in v0.1:

- active camera changes
- controller logs the selection
- userspace UVC streamer restarts
- host receives CAM2

This switching mechanism is intentionally primitive and is expected to change in later versions.

## Checkpoint 10: Focus and Zoom

Select a camera known to expose the relevant V4L2 controls.

Turn the focus encoder.

Expected:

```text
[controller] CAM1: focus 120 -> 125
```

Turn the zoom encoder.

Expected:

```text
[controller] CAM1: zoom 100 -> 101
```

If the controller reports that a control is not exposed, inspect the camera with `v4l2-ctl`.

## Do Not Add OBS Yet

OBS should be introduced only after:

- USB enumeration works
- test pattern works
- CAM1 works
- CAM2 works
- camera switching works
- focus works where supported
- zoom works where supported

That preserves a clean troubleshooting boundary.
