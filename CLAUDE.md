# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An automotive infotainment (IVI) system consisting of three components:
- **STM32F103 firmware** — hardware interface (speed encoder, buttons, ADC potentiometers)
- **Qt5 dashboard** (`software/QtInstrumentCluster/`) — main UI application in C++ + QML
- **Driver Monitoring System** (`software/Driver-Drowsy-Detection/`) — Python AI daemon for drowsiness detection

Runs on Raspberry Pi in production; same Qt app also runs on PC via USB-TTL for development.

## Build & Run

### Qt Dashboard

```bash
cd software/QtInstrumentCluster

# Install dependencies (Raspberry Pi / Debian)
sudo apt-get install qt5-qmake qtbase5-dev qtdeclarative5-dev \
  libqt5serialport5-dev libqt5location5-plugins qtpositioning5-dev \
  qtmultimedia5-dev libdbus-1-dev

# Configure environment
cp .env.example .env
# Edit .env and set MAPBOX_ACCESS_TOKEN=pk.<your_token>

# Build
qmake QtInstrumentCluster.pro
make -j4

# Run
./QtInstrumentCluster
```

Environment variables (from `.env` / shell):
- `MAPBOX_ACCESS_TOKEN` — required for navigation, geocoding, map matching, and map tiles
- `QT_IM_MODULE=qtvirtualkeyboard` and `QT_VIRTUALKEYBOARD_LOCALE=vi_VN` — virtual keyboard (Vietnamese)

### STM32 Firmware

Open `firmware/IVI Automative CP.ioc` in STM32CubeIDE and use Project → Build. Flash via ST-Link.

### Python DMS

```bash
cd software/Driver-Drowsy-Detection
source .venv-pi/bin/activate          # pre-built venv with TF 2.18 + MediaPipe
pip install -r requirements.txt       # or recreate: python3 -m venv .venv-pi

# Control the running daemon
python app/drowsy_camera_ctl.py show    # start / show camera
python app/drowsy_camera_ctl.py hide    # hide (keep model warm)
python app/drowsy_camera_ctl.py status
python app/drowsy_camera_ctl.py stop

# Validate ML pipeline
python scripts/12_validate_pipeline.py
```

### External Services Setup

```bash
# GPS daemon
sudo apt-get install gpsd
sudo service gpsd start

# Bluetooth
sudo systemctl enable bluetooth && sudo service bluetooth start
```

## Architecture

### System Layers

```
STM32 (UART 115200) ─────────────────────────────────────────────────────────┐
gpsd (TCP :2947) ─────────────────────────────────┐                          │
BlueZ (DBus) ──────────────────────────────┐      │                          │
Python DMS (Unix socket /tmp/drowsy_ipc)   │      │                          │
                                           ▼      ▼                          ▼
                      ┌──────────────────────────────────────────────────────────┐
                      │  C++ Services (serialreceiver, gpspositionprovider,      │
                      │  bluetoothcontroller, weatherprovider, osrmrouteprovider,│
                      │  mapboxsearchprovider, mapboxmapmatcher,                 │
                      │  systemsettingscontroller, livecameraitem)               │
                      └───────────────────────┬──────────────────────────────────┘
                                              │ Q_PROPERTY / signals
                                              ▼
                      ┌──────────────────────────────────────────────────────────┐
                      │  QML Singletons: MainModel, TellTalesModel,              │
                      │  NavigationModel, MediaPlayerModel, NormalModeModel,     │
                      │  NavigationFeed, Style, Units                            │
                      └───────────────────────┬──────────────────────────────────┘
                                              │ bindings
                                              ▼
                      ┌──────────────────────────────────────────────────────────┐
                      │  QML Views: main.qml → NormalMode.qml → feature screens  │
                      └──────────────────────────────────────────────────────────┘
```

### Communication Protocols

**UART (STM32 → Qt):** Plain-text frames at 115200 baud
```
DATA:speed=<0-200>,rpm=<0-7000>,fuel=<0-100>,batt=<0-100>,gear=<P|D>\n
BTN:<name>=<ON|OFF>\n
```
`SerialReceiver::autoConnect()` detects `/dev/ttyAMA0` on Pi or `ttyUSB*/ttyACM*` on PC automatically.

**Unix Socket (Qt ↔ Python DMS):** JSON control messages + binary JPEG stream
- Control: `{"command": "show"/"hide"/"status"}` as JSON lines
- Frames: `FRAM` 4-byte magic + 4-byte payload size + JPEG data
- `LiveCameraItem` (QQuickPaintedItem) decodes frames directly in Qt render thread

**HTTP (Qt → Cloud APIs):**
- Mapbox Routing/Geocoding/Map Matching via `QNetworkAccessManager` (class named `OsrmRouteProvider` but uses Mapbox endpoint)
- Open-Meteo weather — falls back to `curl` subprocess if Qt SSL fails on Pi

### Key Files

| File | Role |
|------|------|
| `software/QtInstrumentCluster/main.cpp` | Entry point; registers all C++ QML singletons |
| `src/serialreceiver.cpp` | UART parser; emits typed signals per frame field |
| `src/mainmodel.cpp` | Singleton holding all vehicle telemetry state |
| `src/livecameraitem.cpp` | Renders incoming JPEG stream from Python DMS |
| `src/systemsettingscontroller.cpp` | System commands: nmcli, pactl, amixer, systemctl, sysfs brightness |
| `view/main.qml` | Root QML window; connects SerialReceiver signals to QML models |
| `view/NormalMode.qml` | Main dashboard layout (gauges, status, side panel) |
| `models/MainModel.qml` | Reactive QML singleton for telemetry |
| `models/TellTalesModel.qml` | Warning indicator states with blink timer logic |
| `firmware/Core/Src/uart_protocol.c` | Formats and transmits DATA/BTN frames |
| `app/live_camera_daemon.py` | Background TF inference service; keeps model warm |
| `app/drowsy_ipc.py` | Unix socket IPC protocol definitions |

### Design Decisions Worth Knowing

- **No test framework** — development testing uses keyboard shortcuts defined in `main.qml` (Q, W, E, R, etc. toggle TellTales indicators)
- **Mapbox hard dependency** — `OsrmRouteProvider` name is historical; all routing uses Mapbox APIs
- **DMS daemon stays alive** — Python process keeps TF model loaded; Qt connects/disconnects the socket without restarting the process
- **Vietnamese locale** — `NavigationMapLocation.qml` includes Telex input normalization for search; docs in `/docs/` are in Vietnamese
- **`.venv-pi/`** — non-standard venv name, pre-configured for Raspberry Pi with TF 2.18 + CUDA
