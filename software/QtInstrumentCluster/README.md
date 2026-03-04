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

After setup, re-login (or run `newgrp dialout`), then:

```bash
./scripts/pi/build_pi.sh
./scripts/pi/run_pi.sh
```

If you use UART from STM32, verify serial devices:

```bash
ls -l /dev/ttyAMA0
ls -l /dev/ttyUSB*
```

If no desktop/X11 session is available, run:

```bash
QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi.sh
```

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

