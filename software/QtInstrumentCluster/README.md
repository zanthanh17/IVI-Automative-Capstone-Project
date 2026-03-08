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
- optional Qt WebEngine packages
- tile/OSRM network reachability
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

- Navigation page now tries this order at runtime:
  1. Qt WebEngine + MapLibre GL JS (`web/maplibre_navigation.html`) + OSRM route provider
  2. QtLocation map (`NavigationMapLocation.qml`)
  3. Turn-by-turn HUD fallback (`NavigationHudFallback.qml`)
- This keeps the app usable even when a given Pi image misses some Qt map modules.

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

- If packages are unavailable in your repo, project now auto-builds without `QT += location positioning` and uses Navigation HUD fallback.
- If packages are available, install them then rebuild:

```bash
sudo apt update
sudo apt install -y qt6-location-dev qt6-positioning-dev qml6-module-qtpositioning
./scripts/pi/build_pi.sh
./scripts/pi/verify_pi_env.sh
```

`qml6-module-qtlocation` may be unavailable on Raspberry Pi OS Bookworm repositories.
In that case, use `verify_pi_env.sh` to confirm module/plugin presence and keep HUD fallback enabled.

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

