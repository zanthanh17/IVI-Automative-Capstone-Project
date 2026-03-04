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
5. Simulating data
6. Keyboard event handling

<img src="https://github.com/ShanavasPS/QtInstrumentCluster/assets/8370662/be0ccb51-98ff-49fd-9172-367892e94344" width="800" height="480" alt="Image Alt Text">

### Parked Mode

<img src="https://github.com/ShanavasPS/QtInstrumentCluster/assets/8370662/f5213a2f-87a5-435e-8d48-4a132b6ebb5c" width="800" height="480" alt="qt_cluster_demo_2">

### Drive Mode

<img src="https://github.com/ShanavasPS/QtInstrumentCluster/assets/8370662/02cce851-89b2-4ed3-b9db-274ea6dc15dc" width="800" height="480" alt="qt_cluster_demo_2">

## Keyboard event handling

The following events are handled using the key press

1. Simulation can be paused and resumed by pressing the space bar key
2. The albums can be changed by pressing the left and right arrow keys on the keyboard.

## Raspberry Pi (Native Qt6)

Target: Raspberry Pi OS (Debian-based, e.g. Bookworm), build directly on Pi.

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

