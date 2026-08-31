#!/usr/bin/env bash
#
# pi-camera-controller-setup.sh
# Version 0.1
#
# Raspberry Pi 5 camera-controller bootstrap/configuration utility.
#
# Initial target:
#   - Raspberry Pi OS Lite 64-bit
#   - Headless operation
#   - USB UVC gadget output over the Pi 5 USB-C device port
#   - Two USB cameras
#   - Two GPIO camera-select buttons
#   - Two GPIO rotary encoders: focus and zoom
#   - systemd services + journal logging
#
# This is deliberately a foundation build. OBS/compositing comes later.
#
# IMPORTANT POWER NOTE:
#   On a Pi 5, the USB-C connector used for gadget/device mode is normally
#   also the power connector. Use an appropriate separate 5V supply method
#   before dedicating USB-C to the host PC. Do not improvise power wiring.
#
# Run:
#   chmod +x pi-camera-controller-setup.sh
#   ./pi-camera-controller-setup.sh
#
set -Eeuo pipefail

APP_NAME="Pi Camera Controller"
APP_DIR="/opt/pi-camera-controller"
ETC_DIR="/etc/pi-camera-controller"
CONFIG_FILE="${ETC_DIR}/config.json"
STATE_DIR="/run/pi-camera-controller"
STATE_FILE="${STATE_DIR}/state.json"

CONTROLLER_SERVICE="pi-camera-controller.service"
GADGET_SERVICE="pi-camera-uvc-gadget.service"
UVC_SERVICE="pi-camera-uvc.service"

CONFIG_TXT="/boot/firmware/config.txt"
MODULES_FILE="/etc/modules-load.d/pi-camera-controller.conf"

UVC_SRC="/usr/local/src/uvc-gadget"
# Pin a known 2026-era upstream revision so command-line behavior is reproducible.
UVC_COMMIT="4d9897c5aa5376f89e0d5ed1534536f680939e0d"

DEFAULT_CONFIG='{
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
}'

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

pause_menu() {
    echo
    read -r -p "Press Enter to continue..." _
}

have() {
    command -v "$1" >/dev/null 2>&1
}

sudo_run() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

require_pi_warning() {
    local model=""
    if [[ -r /proc/device-tree/model ]]; then
        model="$(tr -d '\0' </proc/device-tree/model)"
        info "Detected: ${model}"
        if [[ "$model" != *"Raspberry Pi 5"* ]]; then
            warn "This first build is designed and tested conceptually for Raspberry Pi 5."
        fi
    fi
}

ensure_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        info "Creating default configuration at ${CONFIG_FILE}"
        printf '%s\n' "$DEFAULT_CONFIG" | sudo_run install -Dm644 /dev/stdin "$CONFIG_FILE"
    fi
}

json_get() {
    local path="$1"
    python3 - "$CONFIG_FILE" "$path" <<'PY'
import json, sys
fn, path = sys.argv[1], sys.argv[2]
with open(fn) as f:
    d = json.load(f)
for part in path.split("."):
    d = d[part]
if isinstance(d, bool):
    print("true" if d else "false")
else:
    print(d)
PY
}

json_set() {
    local path="$1"
    local value="$2"
    sudo_run python3 - "$CONFIG_FILE" "$path" "$value" <<'PY'
import json, sys, os, tempfile
fn, path, raw = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    value = json.loads(raw)
except Exception:
    value = raw

with open(fn) as f:
    d = json.load(f)

cur = d
parts = path.split(".")
for p in parts[:-1]:
    cur = cur[p]
cur[parts[-1]] = value

fd, tmp = tempfile.mkstemp(prefix=".config-", dir=os.path.dirname(fn))
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, fn)
PY
}

camera_label() {
    local dev="$1"
    if [[ -z "$dev" ]]; then
        echo "(not assigned)"
        return
    fi
    if [[ ! -e "$dev" ]]; then
        echo "${dev} [MISSING]"
        return
    fi
    local name
    name="$(v4l2-ctl -d "$dev" --info 2>/dev/null | awk -F': ' '/Card type/ {print $2; exit}' || true)"
    if [[ -n "$name" ]]; then
        echo "${dev} - ${name}"
    else
        echo "$dev"
    fi
}

# ---------------------------------------------------------------------------
# Generated controller daemon
# ---------------------------------------------------------------------------

install_controller_files() {
    ensure_config

    info "Installing controller runtime files..."

    sudo_run install -d -m755 "$APP_DIR" "$ETC_DIR"

    local tmp
    tmp="$(mktemp)"

    cat >"$tmp" <<'PY'
#!/usr/bin/env python3
"""
Pi Camera Controller runtime daemon, v0.1

- Button 1 selects camera 1
- Button 2 selects camera 2
- Focus encoder changes focus_absolute on active camera
- Zoom encoder changes zoom_absolute on active camera
- State/logging go to /run and journald

The daemon intentionally does not depend on OBS.
"""
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

from gpiozero import Button, RotaryEncoder

CONFIG = Path("/etc/pi-camera-controller/config.json")
STATE_DIR = Path("/run/pi-camera-controller")
STATE = STATE_DIR / "state.json"

lock = threading.RLock()
running = True
active_camera = 1


def log(msg):
    print(f"[controller] {msg}", flush=True)


def load_config():
    with CONFIG.open() as f:
        return json.load(f)


cfg = load_config()


def camera_path(number):
    return cfg.get(f"camera_{number}", "")


def write_state():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    data = {
        "active_camera": active_camera,
        "camera_device": camera_path(active_camera),
        "updated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, STATE)


def run_cmd(args, check=False):
    return subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def list_controls(dev):
    p = run_cmd(["v4l2-ctl", "-d", dev, "--list-ctrls"])
    return p.stdout if p.returncode == 0 else ""


def control_info(dev, name):
    text = list_controls(dev)
    # Example:
    # focus_absolute 0x009a090a (int) : min=0 max=250 step=5 default=0 value=100
    pat = re.compile(
        rf"^\s*{re.escape(name)}\s+.*?"
        r"min=(-?\d+)\s+max=(-?\d+)\s+step=(-?\d+)"
        r".*?value=(-?\d+)",
        re.MULTILINE,
    )
    m = pat.search(text)
    if not m:
        return None
    return {
        "min": int(m.group(1)),
        "max": int(m.group(2)),
        "step": int(m.group(3)),
        "value": int(m.group(4)),
    }


def set_ctrl(dev, name, value, quiet=False):
    p = run_cmd(["v4l2-ctl", "-d", dev, "--set-ctrl", f"{name}={value}"])
    if p.returncode != 0 and not quiet:
        log(f"{dev}: failed to set {name}={value}: {p.stderr.strip()}")
    return p.returncode == 0


def disable_autofocus_if_present(dev):
    text = list_controls(dev)
    for auto_name in ("focus_automatic_continuous", "focus_auto"):
        if re.search(rf"^\s*{re.escape(auto_name)}\s+", text, re.MULTILINE):
            set_ctrl(dev, auto_name, 0, quiet=True)
            return auto_name
    return None


def adjust_control(kind, direction):
    with lock:
        dev = camera_path(active_camera)
        if not dev:
            log(f"CAM{active_camera}: no device assigned; {kind} ignored")
            return
        if not os.path.exists(dev):
            log(f"CAM{active_camera}: {dev} is missing; {kind} ignored")
            return

        control_name = cfg["controls"][kind]
        configured_step = int(cfg["controls"].get(f"{kind}_step", 1))

        if kind == "focus":
            disabled = disable_autofocus_if_present(dev)
            if disabled:
                log(f"CAM{active_camera}: {disabled}=0")

        ci = control_info(dev, control_name)
        if ci is None:
            log(f"CAM{active_camera}: {control_name} not exposed by {dev}")
            return

        # Respect both our desired increment and the camera's native step.
        delta = max(abs(configured_step), abs(ci["step"]) or 1) * direction
        target = max(ci["min"], min(ci["max"], ci["value"] + delta))

        if set_ctrl(dev, control_name, target):
            log(
                f"CAM{active_camera}: {kind} {ci['value']} -> {target} "
                f"(range {ci['min']}..{ci['max']})"
            )


def maybe_restart_usb_stream():
    if not cfg.get("usb", {}).get("restart_stream_on_camera_select", True):
        return

    p = run_cmd(["systemctl", "is-active", "--quiet", "pi-camera-uvc.service"])
    if p.returncode == 0:
        log("Restarting UVC userspace stream for selected camera...")
        # Do not block GPIO callback for long.
        subprocess.Popen(
            ["systemctl", "restart", "pi-camera-uvc.service"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def select_camera(number):
    global active_camera
    with lock:
        active_camera = number
        dev = camera_path(number)
        write_state()
        log(f"CAM{number} selected: {dev or '(not assigned)'}")
        maybe_restart_usb_stream()


def shutdown(signum=None, frame=None):
    global running
    running = False
    log("Stopping")


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

g = cfg["gpio"]

button1 = Button(int(g["button_1"]), pull_up=True, bounce_time=0.05)
button2 = Button(int(g["button_2"]), pull_up=True, bounce_time=0.05)

focus = RotaryEncoder(
    int(g["focus_a"]),
    int(g["focus_b"]),
    max_steps=0,
    wrap=True,
)
zoom = RotaryEncoder(
    int(g["zoom_a"]),
    int(g["zoom_b"]),
    max_steps=0,
    wrap=True,
)

button1.when_pressed = lambda: select_camera(1)
button2.when_pressed = lambda: select_camera(2)

focus.when_rotated_clockwise = lambda: adjust_control("focus", +1)
focus.when_rotated_counter_clockwise = lambda: adjust_control("focus", -1)

zoom.when_rotated_clockwise = lambda: adjust_control("zoom", +1)
zoom.when_rotated_counter_clockwise = lambda: adjust_control("zoom", -1)

write_state()

log("Pi Camera Controller v0.1 started")
log(f"CAM1: {camera_path(1) or '(not assigned)'}")
log(f"CAM2: {camera_path(2) or '(not assigned)'}")
log(
    "GPIO: "
    f"B1={g['button_1']} B2={g['button_2']} "
    f"FOCUS={g['focus_a']}/{g['focus_b']} "
    f"ZOOM={g['zoom_a']}/{g['zoom_b']}"
)

last_heartbeat = 0.0
while running:
    now = time.time()
    if now - last_heartbeat >= 30:
        dev = camera_path(active_camera) or "(not assigned)"
        log(f"heartbeat active=CAM{active_camera} device={dev}")
        last_heartbeat = now
    time.sleep(0.25)

for obj in (button1, button2, focus, zoom):
    try:
        obj.close()
    except Exception:
        pass
PY

    sudo_run install -m755 "$tmp" "${APP_DIR}/controller.py"
    rm -f "$tmp"

    # UVC ConfigFS setup helper.
    tmp="$(mktemp)"
    cat >"$tmp" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/pi-camera-controller/config.json"
ROOT="/sys/kernel/config"
G="${ROOT}/usb_gadget/pi_camera"
F="${G}/functions/uvc.0"

jget() {
    python3 - "$CONFIG" "$1" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d=json.load(f)
for p in sys.argv[2].split("."):
    d=d[p]
print(d)
PY
}

log() { echo "[uvc-config] $*"; }

cleanup() {
    [[ -d "$G" ]] || return 0

    log "Unbinding existing gadget..."
    if [[ -e "$G/UDC" ]]; then
        printf '' >"$G/UDC" 2>/dev/null || true
    fi

    rm -f "$G/configs/c.1/uvc.0" 2>/dev/null || true

    rm -f "$F/streaming/class/fs/h" 2>/dev/null || true
    rm -f "$F/streaming/class/hs/h" 2>/dev/null || true
    rm -f "$F/streaming/class/ss/h" 2>/dev/null || true
    rm -f "$F/streaming/header/h/yuyv" 2>/dev/null || true
    rm -f "$F/control/class/fs/h" 2>/dev/null || true
    rm -f "$F/control/class/ss/h" 2>/dev/null || true

    rmdir "$F/streaming/uncompressed/yuyv/"* 2>/dev/null || true
    rmdir "$F/streaming/uncompressed/yuyv" 2>/dev/null || true
    rmdir "$F/streaming/header/h" 2>/dev/null || true
    rmdir "$F/control/header/h" 2>/dev/null || true
    rmdir "$F" 2>/dev/null || true

    rmdir "$G/configs/c.1/strings/0x409" 2>/dev/null || true
    rmdir "$G/configs/c.1" 2>/dev/null || true
    rmdir "$G/strings/0x409" 2>/dev/null || true
    rmdir "$G" 2>/dev/null || true
}

start() {
    modprobe libcomposite

    if ! mountpoint -q "$ROOT"; then
        mount -t configfs none "$ROOT"
    fi

    cleanup

    local udc width height fps interval product serial
    udc="$(ls /sys/class/udc 2>/dev/null | head -n1 || true)"
    if [[ -z "$udc" ]]; then
        log "ERROR: no USB Device Controller found in /sys/class/udc"
        log "USB peripheral mode probably needs configuring/rebooting."
        exit 1
    fi

    width="$(jget usb.width)"
    height="$(jget usb.height)"
    fps="$(jget usb.fps)"
    product="$(jget usb.product)"
    interval=$((10000000 / fps))
    serial="$(tr -d '-' </etc/machine-id | cut -c1-16)"

    log "UDC: $udc"
    log "Advertising: ${width}x${height} YUYV @ ${fps}fps"

    mkdir -p "$G"
    cd "$G"

    # Development/test VID/PID used by Linux gadget examples.
    # Do not treat these as a commercially assigned VID/PID.
    echo 0x0525 > idVendor
    echo 0xa4a2 > idProduct
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB

    mkdir -p strings/0x409
    echo "$serial" > strings/0x409/serialnumber
    echo "Pi Camera Project" > strings/0x409/manufacturer
    echo "$product" > strings/0x409/product

    mkdir -p configs/c.1/strings/0x409
    echo "UVC Camera" > configs/c.1/strings/0x409/configuration

    mkdir -p "$F"

    frame="$F/streaming/uncompressed/yuyv/${height}p"
    mkdir -p "$frame"
    echo "$width" > "$frame/wWidth"
    echo "$height" > "$frame/wHeight"
    echo $((width * height * 2)) > "$frame/dwMaxVideoFrameBufferSize"
    echo "$interval" > "$frame/dwFrameInterval"

    mkdir -p "$F/streaming/header/h"
    ln -s ../../uncompressed/yuyv "$F/streaming/header/h/yuyv"

    ln -s ../../header/h "$F/streaming/class/fs/h"
    ln -s ../../header/h "$F/streaming/class/hs/h"

    mkdir -p "$F/control/header/h"
    ln -s ../../header/h "$F/control/class/fs/h"
    # Kernel UVC docs define this SS control header link even when the stream
    # itself is limited to USB 2 high speed.
    ln -s ../../header/h "$F/control/class/ss/h"

    echo 1 > "$F/streaming_interval"
    echo 3072 > "$F/streaming_maxpacket"

    ln -s "$F" "$G/configs/c.1/uvc.0"

    echo "$udc" > "$G/UDC"
    log "Gadget bound. Host should enumerate '$product'."
}

case "${1:-}" in
    start) start ;;
    stop) cleanup ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 2
        ;;
esac
SH
    sudo_run install -m755 "$tmp" "${APP_DIR}/uvc-config.sh"
    rm -f "$tmp"

    # UVC userspace streamer wrapper.
    tmp="$(mktemp)"
    cat >"$tmp" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/pi-camera-controller/config.json"
STATE="/run/pi-camera-controller/state.json"

jget() {
    python3 - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d=json.load(f)
for p in sys.argv[2].split("."):
    d=d[p]
print(d)
PY
}

mode="$(jget "$CONFIG" usb.source_mode)"
echo "[uvc-stream] source_mode=${mode}"

if [[ "$mode" == "test" ]]; then
    echo "[uvc-stream] Starting upstream UVC test pattern"
    exec /usr/local/bin/uvc-gadget uvc.0
fi

active=1
if [[ -f "$STATE" ]]; then
    active="$(jget "$STATE" active_camera)"
fi

camera="$(jget "$CONFIG" "camera_${active}")"

if [[ -z "$camera" ]]; then
    echo "[uvc-stream] ERROR: CAM${active} is not assigned"
    exit 1
fi

if [[ ! -e "$camera" ]]; then
    echo "[uvc-stream] ERROR: ${camera} does not exist"
    exit 1
fi

echo "[uvc-stream] CAM${active}: ${camera}"
echo "[uvc-stream] Starting V4L2 -> UVC passthrough"
exec /usr/local/bin/uvc-gadget -d "$camera" uvc.0
SH
    sudo_run install -m755 "$tmp" "${APP_DIR}/uvc-stream.sh"
    rm -f "$tmp"

    # systemd: controller
    tmp="$(mktemp)"
    cat >"$tmp" <<'UNIT'
[Unit]
Description=Pi Camera Controller GPIO Runtime
After=local-fs.target

[Service]
Type=simple
ExecStart=/opt/pi-camera-controller/controller.py
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT
    sudo_run install -m644 "$tmp" "/etc/systemd/system/${CONTROLLER_SERVICE}"
    rm -f "$tmp"

    # systemd: persistent USB gadget descriptor
    tmp="$(mktemp)"
    cat >"$tmp" <<'UNIT'
[Unit]
Description=Pi Camera Controller USB UVC Gadget
After=systemd-modules-load.service local-fs.target
Before=pi-camera-uvc.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/pi-camera-controller/uvc-config.sh start
ExecStop=/opt/pi-camera-controller/uvc-config.sh stop
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT
    sudo_run install -m644 "$tmp" "/etc/systemd/system/${GADGET_SERVICE}"
    rm -f "$tmp"

    # systemd: userspace UVC stream
    tmp="$(mktemp)"
    cat >"$tmp" <<'UNIT'
[Unit]
Description=Pi Camera Controller UVC Video Stream
Requires=pi-camera-uvc-gadget.service
After=pi-camera-uvc-gadget.service

[Service]
Type=simple
ExecStart=/opt/pi-camera-controller/uvc-stream.sh
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT
    sudo_run install -m644 "$tmp" "/etc/systemd/system/${UVC_SERVICE}"
    rm -f "$tmp"

    # journal persistence and log shortcut
    sudo_run install -d -m755 /etc/systemd/journald.conf.d
    printf '%s\n' \
        '[Journal]' \
        'Storage=persistent' \
        'SystemMaxUse=200M' \
        | sudo_run install -Dm644 /dev/stdin /etc/systemd/journald.conf.d/pi-camera-controller.conf

    tmp="$(mktemp)"
    cat >"$tmp" <<'SH'
#!/usr/bin/env bash
exec journalctl -f \
  -u pi-camera-controller.service \
  -u pi-camera-uvc-gadget.service \
  -u pi-camera-uvc.service
SH
    sudo_run install -m755 "$tmp" /usr/local/bin/camera-log
    rm -f "$tmp"

    sudo_run systemctl daemon-reload
    sudo_run systemctl restart systemd-journald

    info "Runtime files installed."
}

# ---------------------------------------------------------------------------
# Packages / headless
# ---------------------------------------------------------------------------

install_packages() {
    info "Installing required packages..."
    sudo_run apt-get update
    sudo_run apt-get install -y \
        git \
        build-essential \
        meson \
        ninja-build \
        pkg-config \
        libjpeg-dev \
        v4l-utils \
        ffmpeg \
        python3-gpiozero \
        python3-lgpio

    info "Package installation complete."
}

set_headless_target() {
    warn "This changes the normal boot target to multi-user (no desktop GUI)."
    read -r -p "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return
    sudo_run systemctl set-default multi-user.target
    info "Default boot target set to multi-user.target."
}

# ---------------------------------------------------------------------------
# Cameras
# ---------------------------------------------------------------------------

discover_camera_paths() {
    local found=0

    # Prefer persistent IDs and only the primary video node for a device.
    if compgen -G "/dev/v4l/by-id/*video-index0" >/dev/null; then
        while IFS= read -r path; do
            printf '%s\n' "$path"
            found=1
        done < <(find /dev/v4l/by-id -maxdepth 1 -type l -name '*video-index0' | sort)
    fi

    if [[ "$found" -eq 0 ]]; then
        for path in /dev/video*; do
            [[ -e "$path" ]] || continue
            # List capture-capable nodes only where possible.
            if v4l2-ctl -d "$path" --all 2>/dev/null | grep -qE 'Video Capture|Video Capture Multiplanar'; then
                printf '%s\n' "$path"
                found=1
            fi
        done
    fi
}

list_cameras() {
    if ! have v4l2-ctl; then
        warn "v4l-utils is not installed. Use menu option 2 first."
        return
    fi

    echo
    echo "V4L2 devices:"
    v4l2-ctl --list-devices || true

    echo
    echo "Suggested persistent camera paths:"
    local i=1
    mapfile -t cams < <(discover_camera_paths)
    if ((${#cams[@]} == 0)); then
        warn "No capture cameras found."
        return
    fi

    for c in "${cams[@]}"; do
        printf '  %d) %s\n' "$i" "$(camera_label "$c")"
        ((i++))
    done
}

assign_camera() {
    ensure_config
    list_cameras
    mapfile -t cams < <(discover_camera_paths)
    ((${#cams[@]} > 0)) || return

    echo
    read -r -p "Assign which logical camera [1/2]? " slot
    [[ "$slot" == "1" || "$slot" == "2" ]] || { warn "Choose 1 or 2."; return; }

    read -r -p "Choose detected device number: " idx
    [[ "$idx" =~ ^[0-9]+$ ]] || { warn "Invalid number."; return; }
    (( idx >= 1 && idx <= ${#cams[@]} )) || { warn "Out of range."; return; }

    json_set "camera_${slot}" "${cams[$((idx-1))]}"
    info "CAM${slot} -> ${cams[$((idx-1))]}"
}

inspect_camera_controls() {
    ensure_config
    echo
    read -r -p "Inspect CAM [1/2]? " slot
    [[ "$slot" == "1" || "$slot" == "2" ]] || return
    local dev
    dev="$(json_get "camera_${slot}")"
    [[ -n "$dev" ]] || { warn "CAM${slot} is not assigned."; return; }
    [[ -e "$dev" ]] || { warn "${dev} does not exist."; return; }

    echo
    echo "Formats:"
    v4l2-ctl -d "$dev" --list-formats-ext || true
    echo
    echo "Controls:"
    v4l2-ctl -d "$dev" --list-ctrls || true
}

# ---------------------------------------------------------------------------
# GPIO configuration / test
# ---------------------------------------------------------------------------

configure_gpio() {
    ensure_config
    echo
    echo "Use BCM GPIO numbers, not physical header pin numbers."
    echo "Current:"
    echo "  Button 1: $(json_get gpio.button_1)"
    echo "  Button 2: $(json_get gpio.button_2)"
    echo "  Focus A/B: $(json_get gpio.focus_a) / $(json_get gpio.focus_b)"
    echo "  Zoom  A/B: $(json_get gpio.zoom_a) / $(json_get gpio.zoom_b)"
    echo
    read -r -p "Change these values? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return

    local b1 b2 fa fb za zb
    read -r -p "Button 1 BCM GPIO: " b1
    read -r -p "Button 2 BCM GPIO: " b2
    read -r -p "Focus encoder A BCM GPIO: " fa
    read -r -p "Focus encoder B BCM GPIO: " fb
    read -r -p "Zoom encoder A BCM GPIO: " za
    read -r -p "Zoom encoder B BCM GPIO: " zb

    for v in "$b1" "$b2" "$fa" "$fb" "$za" "$zb"; do
        [[ "$v" =~ ^[0-9]+$ ]] || { warn "All GPIO values must be integers."; return; }
    done

    json_set gpio.button_1 "$b1"
    json_set gpio.button_2 "$b2"
    json_set gpio.focus_a "$fa"
    json_set gpio.focus_b "$fb"
    json_set gpio.zoom_a "$za"
    json_set gpio.zoom_b "$zb"

    info "GPIO configuration saved."
}

test_gpio_live() {
    ensure_config
    if ! python3 -c 'import gpiozero' >/dev/null 2>&1; then
        warn "gpiozero not available. Install packages first."
        return
    fi

    local b1 b2 fa fb za zb
    b1="$(json_get gpio.button_1)"
    b2="$(json_get gpio.button_2)"
    fa="$(json_get gpio.focus_a)"
    fb="$(json_get gpio.focus_b)"
    za="$(json_get gpio.zoom_a)"
    zb="$(json_get gpio.zoom_b)"

    echo
    echo "Live GPIO test. Press buttons / turn encoders. Ctrl-C exits."
    echo "B1=${b1} B2=${b2} FOCUS=${fa}/${fb} ZOOM=${za}/${zb}"
    echo

    python3 - "$b1" "$b2" "$fa" "$fb" "$za" "$zb" <<'PY'
from gpiozero import Button, RotaryEncoder
from signal import pause
import sys, time

b1, b2, fa, fb, za, zb = map(int, sys.argv[1:])

def p(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)

button1 = Button(b1, pull_up=True, bounce_time=0.05)
button2 = Button(b2, pull_up=True, bounce_time=0.05)
focus = RotaryEncoder(fa, fb, max_steps=0, wrap=True)
zoom  = RotaryEncoder(za, zb, max_steps=0, wrap=True)

button1.when_pressed = lambda: p("BUTTON 1 -> CAM1")
button2.when_pressed = lambda: p("BUTTON 2 -> CAM2")

focus.when_rotated_clockwise = lambda: p("FOCUS +")
focus.when_rotated_counter_clockwise = lambda: p("FOCUS -")
zoom.when_rotated_clockwise = lambda: p("ZOOM +")
zoom.when_rotated_counter_clockwise = lambda: p("ZOOM -")

p("GPIO test started")
try:
    pause()
except KeyboardInterrupt:
    p("GPIO test stopped")
PY
}

# ---------------------------------------------------------------------------
# Pi 5 USB peripheral mode
# ---------------------------------------------------------------------------

configure_usb_peripheral_mode() {
    [[ -f "$CONFIG_TXT" ]] || die "Cannot find ${CONFIG_TXT}"

    warn "This modifies ${CONFIG_TXT} and requires a reboot."
    warn "The Pi 5 USB-C connector will be dedicated to USB device/gadget mode."
    warn "Make sure you have a safe separate power plan before relying on it."
    echo
    read -r -p "Configure USB peripheral mode? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return

    sudo_run cp -a "$CONFIG_TXT" "${CONFIG_TXT}.pre-pi-camera-controller"

    sudo_run python3 - "$CONFIG_TXT" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
text = p.read_text()

# Avoid a Pi 5 host-mode overlay fighting our peripheral overlay.
lines = []
for line in text.splitlines():
    if re.match(r'^\s*dtoverlay=dwc2,dr_mode=host\s*$', line):
        lines.append("# pi-camera-controller disabled host mode: " + line)
    elif line.strip() == "dtoverlay=dwc2,dr_mode=peripheral":
        # We'll add our managed block below once.
        continue
    else:
        lines.append(line)

marker = "# --- pi-camera-controller USB gadget mode ---"
clean = []
skip = False
for line in lines:
    if line.strip() == marker:
        skip = True
        continue
    if skip:
        # Our managed block has exactly two subsequent lines.
        if line.strip() in ("[all]", "dtoverlay=dwc2,dr_mode=peripheral"):
            continue
        skip = False
    clean.append(line)

clean += [
    "",
    marker,
    "[all]",
    "dtoverlay=dwc2,dr_mode=peripheral",
]

p.write_text("\n".join(clean).rstrip() + "\n")
PY

    printf 'dwc2\nlibcomposite\n' | sudo_run install -Dm644 /dev/stdin "$MODULES_FILE"

    info "USB peripheral mode configured."
    warn "Reboot is required before /sys/class/udc will show the device controller."
}

usb_status() {
    echo
    echo "USB gadget prerequisites:"
    echo "  Config overlay:"
    grep -n 'dwc2' "$CONFIG_TXT" 2>/dev/null || true
    echo
    echo "  Loaded modules:"
    lsmod | grep -E 'dwc2|libcomposite' || true
    echo
    echo "  Device controllers:"
    if [[ -d /sys/class/udc ]]; then
        ls -1 /sys/class/udc 2>/dev/null || true
    fi
    echo
    if [[ -d "/sys/kernel/config/usb_gadget/pi_camera" ]]; then
        echo "  Gadget exists: yes"
        echo -n "  Bound UDC: "
        cat /sys/kernel/config/usb_gadget/pi_camera/UDC 2>/dev/null || true
    else
        echo "  Gadget exists: no"
    fi
}

# ---------------------------------------------------------------------------
# uvc-gadget userspace app
# ---------------------------------------------------------------------------

install_uvc_gadget() {
    have git || { warn "git not installed. Install packages first."; return; }
    have meson || { warn "meson not installed. Install packages first."; return; }
    have ninja || { warn "ninja not installed. Install packages first."; return; }

    info "Installing upstream uvc-gadget userspace app..."
    sudo_run install -d -m755 /usr/local/src

    if [[ ! -d "${UVC_SRC}/.git" ]]; then
        sudo_run git clone https://gitlab.freedesktop.org/camera/uvc-gadget.git "$UVC_SRC"
    fi

    sudo_run git -C "$UVC_SRC" fetch --tags origin
    sudo_run git -C "$UVC_SRC" checkout --detach "$UVC_COMMIT"

    sudo_run rm -rf "${UVC_SRC}/build"
    sudo_run meson setup "${UVC_SRC}/build" "$UVC_SRC" --buildtype=release
    sudo_run ninja -C "${UVC_SRC}/build"
    sudo_run meson install -C "${UVC_SRC}/build"
    sudo_run ldconfig

    if [[ -x /usr/local/bin/uvc-gadget ]]; then
        info "Installed: /usr/local/bin/uvc-gadget"
        /usr/local/bin/uvc-gadget -h 2>&1 | head -30 || true
    else
        warn "Build completed but /usr/local/bin/uvc-gadget was not found."
    fi
}

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------

enable_controller_service() {
    install_controller_files
    sudo_run systemctl enable --now "$CONTROLLER_SERVICE"
    info "${CONTROLLER_SERVICE} enabled and started."
}

stop_controller_service() {
    sudo_run systemctl disable --now "$CONTROLLER_SERVICE" 2>/dev/null || true
    info "${CONTROLLER_SERVICE} stopped/disabled."
}

start_usb_test_pattern() {
    ensure_config
    [[ -x /usr/local/bin/uvc-gadget ]] || {
        warn "uvc-gadget is not installed. Use the install option first."
        return
    }

    if ! ls /sys/class/udc/* >/dev/null 2>&1; then
        warn "No USB Device Controller is visible. Configure peripheral mode and reboot first."
        return
    fi

    install_controller_files
    json_set usb.source_mode test

    sudo_run systemctl enable "$GADGET_SERVICE"
    sudo_run systemctl restart "$GADGET_SERVICE"
    sudo_run systemctl enable "$UVC_SERVICE"
    sudo_run systemctl restart "$UVC_SERVICE"

    info "USB UVC test-pattern stream started."
    info "Connect the Pi 5 USB-C gadget cable to the host and select 'Pi Camera Controller'."
}

start_usb_camera_stream() {
    ensure_config
    [[ -x /usr/local/bin/uvc-gadget ]] || {
        warn "uvc-gadget is not installed."
        return
    }

    local c1
    c1="$(json_get camera_1)"
    [[ -n "$c1" ]] || {
        warn "Assign at least CAM1 before starting camera passthrough."
        return
    }

    if ! ls /sys/class/udc/* >/dev/null 2>&1; then
        warn "No USB Device Controller is visible. Configure peripheral mode and reboot first."
        return
    fi

    install_controller_files
    json_set usb.source_mode camera

    sudo_run install -d -m755 "$STATE_DIR"
    if [[ ! -f "$STATE_FILE" ]]; then
        printf '{"active_camera": 1}\n' | sudo_run install -Dm644 /dev/stdin "$STATE_FILE"
    fi

    sudo_run systemctl enable "$GADGET_SERVICE"
    sudo_run systemctl restart "$GADGET_SERVICE"
    sudo_run systemctl enable "$UVC_SERVICE"
    sudo_run systemctl restart "$UVC_SERVICE"

    info "USB camera passthrough started."
    warn "v0.1 assumes the selected camera can satisfy the advertised UVC format."
    warn "If the host sees a camera but no image, inspect formats/controls and logs."
}

stop_usb_stream() {
    sudo_run systemctl disable --now "$UVC_SERVICE" 2>/dev/null || true
    sudo_run systemctl disable --now "$GADGET_SERVICE" 2>/dev/null || true
    info "USB stream and gadget stopped."
}

toggle_usb_camera_restart() {
    ensure_config
    local cur
    cur="$(json_get usb.restart_stream_on_camera_select)"
    if [[ "$cur" == "true" ]]; then
        json_set usb.restart_stream_on_camera_select false
        info "Camera buttons will NOT restart the USB video stream."
    else
        json_set usb.restart_stream_on_camera_select true
        info "Camera buttons WILL restart the UVC userspace streamer."
    fi
}

follow_logs() {
    echo
    echo "Following controller/UVC logs. Ctrl-C exits."
    echo
    if have camera-log; then
        sudo_run camera-log
    else
        sudo_run journalctl -f \
            -u "$CONTROLLER_SERVICE" \
            -u "$GADGET_SERVICE" \
            -u "$UVC_SERVICE"
    fi
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

service_state() {
    local s="$1"
    systemctl is-active "$s" 2>/dev/null || true
}

show_status() {
    ensure_config

    echo
    echo "============================================================"
    echo " ${APP_NAME} - Status"
    echo "============================================================"
    echo
    require_pi_warning
    echo
    echo "OS:"
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        echo "  ${PRETTY_NAME:-unknown}"
    fi
    echo "  Kernel: $(uname -r)"
    echo
    echo "Cameras:"
    echo "  CAM1: $(camera_label "$(json_get camera_1)")"
    echo "  CAM2: $(camera_label "$(json_get camera_2)")"
    echo
    echo "GPIO:"
    echo "  Button 1: BCM $(json_get gpio.button_1)"
    echo "  Button 2: BCM $(json_get gpio.button_2)"
    echo "  Focus:    BCM $(json_get gpio.focus_a) / $(json_get gpio.focus_b)"
    echo "  Zoom:     BCM $(json_get gpio.zoom_a) / $(json_get gpio.zoom_b)"
    echo
    echo "USB output:"
    echo "  Product:  $(json_get usb.product)"
    echo "  Format:   $(json_get usb.width)x$(json_get usb.height) YUYV @ $(json_get usb.fps) fps"
    echo "  Source:   $(json_get usb.source_mode)"
    echo "  Switch restarts stream: $(json_get usb.restart_stream_on_camera_select)"
    echo
    echo "Services:"
    printf '  %-33s %s\n' "$CONTROLLER_SERVICE" "$(service_state "$CONTROLLER_SERVICE")"
    printf '  %-33s %s\n' "$GADGET_SERVICE" "$(service_state "$GADGET_SERVICE")"
    printf '  %-33s %s\n' "$UVC_SERVICE" "$(service_state "$UVC_SERVICE")"
    echo
    if [[ -f "$STATE_FILE" ]]; then
        echo "Runtime state:"
        cat "$STATE_FILE"
        echo
    fi
    echo "UDC:"
    ls -1 /sys/class/udc 2>/dev/null || echo "  (none visible; reboot/config may still be required)"
}

show_config() {
    ensure_config
    python3 -m json.tool "$CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# Full first-pass setup
# ---------------------------------------------------------------------------

first_pass_setup() {
    echo
    echo "This will:"
    echo "  - install packages"
    echo "  - create the default config"
    echo "  - install controller/UVC runtime files"
    echo "  - configure Pi 5 USB peripheral mode"
    echo "  - build upstream uvc-gadget"
    echo
    echo "It will NOT choose your two cameras or start streaming."
    echo
    read -r -p "Run first-pass setup? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return

    install_packages
    ensure_config
    install_controller_files
    configure_usb_peripheral_mode
    install_uvc_gadget

    echo
    info "First-pass setup complete."
    warn "A reboot is required for USB peripheral mode."
    warn "After reboot, return to this menu, assign cameras, then test GPIO and USB."
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

menu() {
    while true; do
        clear || true
        echo "============================================================"
        echo " ${APP_NAME} - Setup / Configuration v0.1"
        echo "============================================================"
        echo
        echo "  1) Status"
        echo "  2) First-pass setup"
        echo
        echo "  3) Install/update required packages"
        echo "  4) Detect/list cameras"
        echo "  5) Assign CAM1 or CAM2"
        echo "  6) Inspect camera formats + focus/zoom controls"
        echo
        echo "  7) Configure GPIO pins"
        echo "  8) Live-test buttons + rotary encoders"
        echo "  9) Install/refresh controller runtime + systemd files"
        echo " 10) Start controller service"
        echo " 11) Stop controller service"
        echo
        echo " 12) Configure Pi 5 USB peripheral mode"
        echo " 13) USB gadget status"
        echo " 14) Build/install upstream uvc-gadget"
        echo " 15) Start USB TEST PATTERN"
        echo " 16) Start USB ACTIVE CAMERA passthrough"
        echo " 17) Stop USB video"
        echo " 18) Toggle camera-button USB stream restart"
        echo
        echo " 19) Follow live camera logs"
        echo " 20) Show raw configuration"
        echo " 21) Set boot target to headless"
        echo " 22) Reboot"
        echo
        echo "  0) Exit"
        echo
        read -r -p "Choice: " choice

        case "$choice" in
            1)  show_status; pause_menu ;;
            2)  first_pass_setup; pause_menu ;;
            3)  install_packages; pause_menu ;;
            4)  list_cameras; pause_menu ;;
            5)  assign_camera; pause_menu ;;
            6)  inspect_camera_controls; pause_menu ;;
            7)  configure_gpio; pause_menu ;;
            8)  test_gpio_live; pause_menu ;;
            9)  install_controller_files; pause_menu ;;
            10) enable_controller_service; pause_menu ;;
            11) stop_controller_service; pause_menu ;;
            12) configure_usb_peripheral_mode; pause_menu ;;
            13) usb_status; pause_menu ;;
            14) install_uvc_gadget; pause_menu ;;
            15) start_usb_test_pattern; pause_menu ;;
            16) start_usb_camera_stream; pause_menu ;;
            17) stop_usb_stream; pause_menu ;;
            18) toggle_usb_camera_restart; pause_menu ;;
            19) follow_logs ;;
            20) show_config; pause_menu ;;
            21) set_headless_target; pause_menu ;;
            22)
                read -r -p "Reboot now? [y/N] " ans
                if [[ "$ans" =~ ^[Yy]$ ]]; then
                    sudo_run reboot
                fi
                ;;
            0) exit 0 ;;
            *) warn "Unknown choice."; sleep 1 ;;
        esac
    done
}

main() {
    if ! have python3; then
        die "python3 is required."
    fi

    require_pi_warning
    ensure_config
    menu
}

main "$@"
