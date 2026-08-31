# Troubleshooting

> **Status: initial troubleshooting guide. Most failure modes have not yet been observed on real target hardware.**

The project intentionally separates GPIO, camera, USB gadget, and userspace video components so each layer can be tested independently.

Start with the simplest failing layer.

## Follow All Project Logs

```bash
camera-log
```

This follows:

```text
pi-camera-controller.service
pi-camera-uvc-gadget.service
pi-camera-uvc.service
```

Individual logs:

```bash
journalctl -u pi-camera-controller.service
journalctl -u pi-camera-uvc-gadget.service
journalctl -u pi-camera-uvc.service
```

## Check Service Status

```bash
systemctl status pi-camera-controller.service
systemctl status pi-camera-uvc-gadget.service
systemctl status pi-camera-uvc.service
```

## Camera Does Not Appear on the Pi

Run:

```bash
lsusb
v4l2-ctl --list-devices
```

Check:

- camera power
- USB cable
- powered hub
- different Pi USB port
- whether the camera appears in `lsusb`
- whether a `/dev/video*` node exists

## Camera Device Number Changes After Reboot

Do not depend on:

```text
/dev/video0
/dev/video1
```

Check:

```bash
ls -l /dev/v4l/by-id/
```

Use persistent `video-index0` paths where available.

## Camera Has Video but Focus Encoder Does Nothing

Inspect controls:

```bash
v4l2-ctl -d /dev/video0 --list-ctrls
```

Look for:

```text
focus_absolute
focus_auto
```

Possible causes:

- camera does not support manual focus
- autofocus must be disabled first
- control name differs
- camera node is not the correct capture/control node

## Zoom Encoder Does Nothing

Inspect:

```bash
v4l2-ctl -d /dev/video0 --list-ctrls
```

Look for:

```text
zoom_absolute
```

Many webcams do not provide true hardware zoom.

Future OBS integration may provide digital zoom independently of camera hardware.

## Focus or Zoom Moves the Wrong Direction

The encoder A/B connections may be reversed.

Options:

- swap encoder A and B wires
- later add an invert setting to configuration

## Camera Button Does Nothing

First stop the permanent controller if necessary, then run the live GPIO test from the menu:

```text
8) Live-test buttons + rotary encoders
```

Expected:

```text
BUTTON 1 -> CAM1
BUTTON 2 -> CAM2
```

If no event appears:

- verify BCM numbering
- verify button is wired between configured GPIO and GND
- verify common ground
- verify the configured GPIO values

## Rotary Encoder Produces No Events

Use the same live GPIO test.

Check:

- encoder common is connected to GND
- A and B use the configured GPIO pins
- module power requirements if using an encoder breakout
- BCM vs physical pin numbering

## `/sys/class/udc` Is Empty

Run:

```bash
ls /sys/class/udc
grep -n dwc2 /boot/firmware/config.txt
lsmod | grep -E 'dwc2|libcomposite'
```

Likely causes:

- USB peripheral overlay not configured
- reboot has not occurred
- conflicting `dwc2` mode configuration
- unsupported or incorrect boot configuration

Do not troubleshoot UVC video until a UDC is visible.

## Host PC Does Not See `Pi Camera Controller`

Check on the Pi:

```bash
ls /sys/class/udc
systemctl status pi-camera-uvc-gadget.service
camera-log
```

Also check:

- USB cable supports data
- cable is connected to the correct Pi 5 USB-C port
- host USB port works
- Pi has a safe independent power arrangement
- ConfigFS gadget is bound to the UDC

## Host Sees Camera but There Is No Video

This is an important distinction.

If the host enumerates the camera, then much of the USB gadget descriptor path is already working.

Focus on:

```bash
systemctl status pi-camera-uvc.service
journalctl -u pi-camera-uvc.service
```

Try the test pattern before a real camera.

If the test pattern works but camera passthrough fails, investigate camera formats and the userspace pipeline.

## Test Pattern Works but Real Camera Does Not

Inspect:

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
```

The current prototype assumes the physical camera can supply a format compatible with the advertised UVC configuration.

That assumption is expected to be refined after real hardware testing.

## USB Video Breaks When Switching CAM1/CAM2

The v0.1 implementation restarts the userspace UVC streamer when the logical camera changes.

This is a temporary implementation.

Check:

```bash
camera-log
```

Expected sequence:

```text
CAM2 selected
Restarting UVC userspace stream for selected camera...
[uvc-stream] CAM2: ...
```

If the host application does not recover cleanly after the restart, document the behavior.

OBS-based switching is planned specifically to avoid rebuilding/restarting the host-facing stream for every camera change.

## Pi Reports Undervoltage or USB Instability

Check:

```bash
vcgencmd get_throttled
dmesg | grep -i -E 'voltage|under-voltage|usb'
```

Possible causes:

- inadequate Pi power
- too many bus-powered cameras
- unpowered hub
- marginal cables

Do not debug video software until power stability is established.

## Useful Diagnostic Bundle

When filing an issue, include:

```bash
uname -a
cat /etc/os-release
lsusb
v4l2-ctl --list-devices
ls /sys/class/udc
systemctl status pi-camera-controller.service
systemctl status pi-camera-uvc-gadget.service
systemctl status pi-camera-uvc.service
```

Also include for each relevant camera:

```bash
v4l2-ctl -d <device> --list-formats-ext
v4l2-ctl -d <device> --list-ctrls
```
