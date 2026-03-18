# QtInstrumentCluster

A basic Instrument cluster application that demonstrates integrating QML and C++.
This application is leveraged from [Qt Quick Ultralite Automotive Cluster Demo
](https://doc.qt.io/QtForMCUs-2.5/quickultralite-automotive-example.html)
, but without the use of Qt Quick Ultralite as it is only available under commercial license.

The main focus points are to prove the following skills:
1. Knowledge and hands-on experience in Qt
2. Integrating QML and C++
3. Usage of signals and slots
4. Usage of Singleton classes
5. Hardware telemetry integration (UART)
6. Keyboard event handling

<img src="https://github.com/ShanavasPS/QtInstrumentCluster/assets/8370662/be0ccb51-98ff-49fd-9172-367892e94344" width="800" height="480" alt="Image Alt Text">

### Parked Mode

<img src="https://github.com/ShanavasPS/QtInstrumentCluster/assets/8370662/f5213a2f-87a5-435e-8d48-4a132b6ebb5c" width="800" height="480" alt="qt_cluster_demo_2">

### Drive Mode

<img src="https://github.com/ShanavasPS/QtInstrumentCluster/assets/8370662/02cce851-89b2-4ed3-b9db-274ea6dc15dc" width="800" height="480" alt="qt_cluster_demo_2">

## Keyboard event handling

The following events are handled using key press:

1. `Left` / `Right`: previous or next media item
2. `N` / `M`: switch dashboard menu
3. `Q`, `E`, `W`, `R`, `T`, `Y`: toggle telltales for quick UI validation
4. `G`: toggle navigation feed source (mock GPS / hardware GPS)
5. `H`: toggle external media host mode
6. `B`: rescan local host media tracks

## Raspberry Pi (Native Qt6)

Target: Raspberry Pi OS (Debian-based, e.g. Bookworm), build directly on Pi.
Note: On many Pi OS repos, `qml6-module-qtquick-effects` does not exist.
Current UI no longer depends on that package.

From `software/QtInstrumentCluster`:

```bash
chmod +x scripts/pi/*.sh
./scripts/pi/setup_pi_native_qt6.sh
```

The setup script now attempts to install Qt map modules (`QtLocation` / `QtPositioning`) when available in your apt repository:
- `qt6-location-dev`, `qt6-positioning-dev`, `qt6-location-dev-tools`
- `qml6-module-qtlocation`, `qml6-module-qtpositioning`

If your distro repo does not provide them, Navigation map cannot use QtLocation and will fall back to turn-by-turn HUD.

After setup, re-login (or run `newgrp dialout`), then:

```bash
./scripts/pi/build_pi.sh
./scripts/pi/verify_pi_env.sh
./scripts/pi/run_pi.sh
```

`verify_pi_env.sh` performs a preflight check:
- Qt6 toolchain/runtime packages
- Qt Location plugin availability
- Mapbox API network reachability
- serial permission (`dialout`) and device node presence

If you use UART from STM32, verify serial devices:

```bash
ls -l /dev/ttyAMA0
ls -l /dev/ttyUSB*
```

If no desktop/X11 session is available, run:

```bash
QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi.sh
```

### Navigation map behavior

- Navigation page is now **Mapbox-only** via QtLocation `mapboxgl` plugin (`NavigationMapLocation.qml`).
- WebEngine map fallback has been removed.
- Required env vars:
  - `MAPBOX_ACCESS_TOKEN`
  - `MAPBOX_STYLE_URL` (optional; default is fixed `mapbox://styles/mapbox/navigation-guidance-night-v2



`)
- Dashboard map controls use icon buttons (zoom in/out, compass heading, follow toggle, recenter; long-press recenter for route overview).
- Map attribution may still include OpenStreetMap because Mapbox style sources include OSM-derived data and attribution is mandatory by license.

### Bluetooth Audio + Dashboard Controls (Phone -> Pi)

The app supports Linux external media control via BlueZ AVRCP (`org.bluez.MediaPlayer1`).

1. Ensure Bluetooth service is enabled:

```bash
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
```

2. Pair and trust phone with `bluetoothctl`:

```bash
bluetoothctl
power on
agent on
default-agent
scan on
pair <PHONE_MAC>
trust <PHONE_MAC>
connect <PHONE_MAC>
```

3. Start music on phone. Audio should play on Pi via PulseAudio Bluetooth sink.
4. Open Media page on dashboard and keep External mode enabled (`H` key toggles it).
5. Use dashboard controls for Play/Pause/Next/Previous.

If playback works but controls do not, verify device supports AVRCP media control profile.

### Troubleshooting

If you see `module "QtQml.WorkerScript" is not installed`, install missing QML runtime modules:

```bash
sudo apt update
sudo apt install -y qml6-module-qtqml qml6-module-qtqml-models qml6-module-qtqml-workerscript
```

If Pi build shows `Project ERROR: Unknown module(s) in QT: location`:

```bash
qmake6 -query QT_VERSION
dpkg -l | grep -E 'qt6-location-dev|qt6-positioning-dev|qml6-module-qtpositioning'
apt-cache search qt6 | grep -E 'location|positioning'
```

- If packages are unavailable in your repo, Mapbox navigation cannot run on this image.
- If packages are available, install them then rebuild:

```bash
sudo apt update
sudo apt install -y qt6-location-dev qt6-positioning-dev qml6-module-qtpositioning
./scripts/pi/build_pi.sh
./scripts/pi/verify_pi_env.sh
```

`qml6-module-qtlocation` may be unavailable on Raspberry Pi OS Bookworm repositories.
In that case, use `verify_pi_env.sh` to confirm module/plugin presence and switch to a repo/image that provides Qt Location modules.

If Pi build shows `Project ERROR: Unknown module(s) in QT: svg`:

```bash
qmake6 -query QT_VERSION
dpkg -l | grep -E 'qt6-svg-dev|libqt6svg6'
```

Install missing SVG packages, then rebuild:

```bash
sudo apt update
sudo apt install -y qt6-svg-dev
./scripts/pi/build_pi.sh
```

## Raspberry Pi (Native Qt5)

Use this flow when your target image uses Qt5 runtime/toolchain.

From `software/QtInstrumentCluster`:

```bash
chmod +x scripts/pi/*.sh
# Optional: remove Qt6 stack then install Qt5 stack
./scripts/pi/migrate_qt6_to_qt5.sh

# Or install Qt5 directly (without removing Qt6):
./scripts/pi/setup_pi_native_qt5.sh
./scripts/pi/build_pi_qt5.sh
./scripts/pi/verify_pi_qt5.sh
./scripts/pi/run_pi_qt5.sh
```

Notes:
- Qt5 build output is isolated in `build-pi-qt5/` (does not overwrite Qt6 build output).
- If both Qt5 and Qt6 are installed, `build_pi_qt5.sh` explicitly resolves a Qt5 qmake.
- Put `MAPBOX_ACCESS_TOKEN` in `.env` (or export in shell) for Mapbox map + Search Box + routing on Qt5.
- `MAPBOX_STYLE_URL` is optional; Qt5 flow defaults to `mapbox://styles/mapbox/navigation-guidance-night-v2



`.
- Qt5 flow is Mapbox-only (no WebEngine fallback).
- Qt Virtual Keyboard is enabled for text boxes (`QT_IM_MODULE=qtvirtualkeyboard`), default keyboard locale is Vietnamese (`QT_VIRTUALKEYBOARD_LOCALE=vi_VN`).
- If keyboard logs `module "Qt.labs.folderlistmodel" is not installed`, install:
  `sudo apt install -y qml-module-qt-labs-folderlistmodel qml-module-qt-labs-settings qml-module-qt-labs-platform`
- Destination search now applies Vietnamese Telex normalization, uses the Mapbox Search Box `/suggest` + `/retrieve` flow, biases results to the live vehicle position when GPS is available, and uses routable points when present for better turn-by-turn routing.
- Optional search tuning env vars:
  `MAPBOX_SEARCH_LANGUAGE=vi`, `MAPBOX_SEARCH_COUNTRY=VN`, `MAPBOX_SEARCH_LIMIT=8`

### Driver Drowsiness Camera Launcher (Qt5)

- The bottom-bar `Camera` icon now calls `Driver-Drowsy-Detection/app/drowsy_camera_ctl.py show`.
- The detector itself runs as a persistent background daemon (`live_camera_daemon.py`) and keeps the camera/model warm.
- The visible window is now a lightweight viewer client (`live_camera_viewer.py`), so clicking `Camera` no longer restarts the detector.
- The Qt dashboard still stays on the current page after clicking `Camera`.
- Each `show` request also forwards the current GUI session environment (`DISPLAY` / `XAUTHORITY` / `XDG_RUNTIME_DIR` / Wayland vars), so a daemon started earlier by `systemd --user` can still pop the viewer correctly on Pi.

Recommended `.env` values for Raspberry Pi:

```bash
DROWSY_CAMERA_INDEX=0
DROWSY_WIDTH=1024
DROWSY_HEIGHT=600
DROWSY_FPS=30
# Prefer venv python on Pi:
# DROWSY_PYTHON=/home/pi/IVI-Automative-Capstone-Project/software/Driver-Drowsy-Detection/.venv-pi/bin/python3
# Optional explicit control script path:
# DROWSY_CAMERA_CTL_SCRIPT=/home/pi/IVI-Automative-Capstone-Project/software/Driver-Drowsy-Detection/app/drowsy_camera_ctl.py
# Optional daemon socket path:
# DROWSY_DAEMON_SOCKET=/run/user/1000/drowsy-camera-daemon.sock
# Optional fixed camera node:
# DROWSY_CAMERA_PATH=/dev/video0
# Optional scan range when using camera-index:
# DROWSY_FALLBACK_SCAN_MAX=6
# Optional viewer behavior:
# DROWSY_VIEWER_FULLSCREEN=1
# DROWSY_VIEWER_TITLE=Driver Camera
# DROWSY_VIEWER_WIDTH=1024
# DROWSY_VIEWER_HEIGHT=600
```

When the icon is clicked, Qt forwards:
1. `show`
2. `--start-daemon-if-needed`
3. `--backend`
4. `--width` / `--height`
5. `--fps`
6. `--camera-path` or `--camera-index` + `--fallback-scan-max`

If performance drops, reduce first:
1. `DROWSY_WIDTH` / `DROWSY_HEIGHT` (e.g. `640x360`)
2. `DROWSY_FPS`
3. camera source selection (`DROWSY_CAMERA_PATH` or `DROWSY_CAMERA_INDEX`)

Repeated clicks do not restart the detector. If the daemon is already alive, Qt only asks it to show the viewer.
