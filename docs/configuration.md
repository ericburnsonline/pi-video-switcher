# Configuration

> **Status: documents the initial v0.1 configuration format. Fields may change during hardware bring-up.**

Persistent project configuration is stored at:

```text
/etc/pi-camera-controller/config.json
```

The setup menu should be used for normal configuration where possible.

## Current Configuration Structure

The initial structure resembles:

```json
{
  "version": 1,
  "camera_1": "",
  "camera_2": "",
  "gpio": {
    "button_1": 5,
    "button_2": 6,
    "focus_a": 17,
    "focus_b": 27,
    "zoom_a": 22,
    "zoom_b": 23
  },
  "controls": {
    "focus": "focus_absolute",
    "focus_step": 5,
    "zoom": "zoom_absolute",
    "zoom_step": 1
  },
  "usb": {
    "product": "Pi Camera Controller",
    "width": 640,
    "height": 360,
    "fps": 30,
    "source_mode": "test",
    "restart_stream_on_camera_select": true
  }
}
```

## Camera Assignments

```text
camera_1
camera_2
```

These map logical cameras to Linux V4L2 devices.

Persistent paths under:

```text
/dev/v4l/by-id/
```

are preferred when available.

Example:

```json
"camera_1": "/dev/v4l/by-id/usb-example-camera-video-index0"
```

## GPIO

The project uses BCM numbering.

Defaults:

```json
"gpio": {
  "button_1": 5,
  "button_2": 6,
  "focus_a": 17,
  "focus_b": 27,
  "zoom_a": 22,
  "zoom_b": 23
}
```

These values can be changed through the text menu.

## Camera Control Names

Defaults:

```json
"controls": {
  "focus": "focus_absolute",
  "focus_step": 5,
  "zoom": "zoom_absolute",
  "zoom_step": 1
}
```

Different webcams may expose different controls.

Inspect a camera with:

```bash
v4l2-ctl -d /dev/video0 --list-ctrls
```

Do not assume all webcams support manual focus or optical zoom.

## USB Output

Initial USB output:

```json
"usb": {
  "product": "Pi Camera Controller",
  "width": 640,
  "height": 360,
  "fps": 30,
  "source_mode": "test",
  "restart_stream_on_camera_select": true
}
```

### `product`

The name presented to the USB host.

### `width`, `height`, `fps`

The initial UVC format advertised by the gadget configuration.

The v0.1 defaults are intentionally conservative.

### `source_mode`

Current planned values:

```text
test
camera
```

`test` uses the UVC userspace application's test pattern.

`camera` uses the currently selected physical camera.

### `restart_stream_on_camera_select`

When enabled, changing the active camera restarts the userspace UVC streamer.

This is a temporary v0.1 switching mechanism.

Later OBS integration should allow switching without restarting the output transport.

## Runtime State

Runtime state is currently stored under:

```text
/run/pi-camera-controller/state.json
```

Because `/run` is temporary, this state is not intended to survive reboot.

The initial runtime state includes the active camera.

## Planned Persistent Camera State

An early future revision should add per-camera settings such as:

```json
{
  "camera_1": {
    "focus": 145,
    "zoom": 110,
    "autofocus": false
  },
  "camera_2": {
    "focus": 90,
    "zoom": 100,
    "autofocus": true
  }
}
```

The controller should then restore those settings when the cameras become available after boot.

To avoid excessive storage writes, encoder changes should be debounced in memory and written only after a short idle period rather than once per encoder detent.
