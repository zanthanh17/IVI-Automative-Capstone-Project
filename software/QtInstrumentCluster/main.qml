import QtQuick 2.12
import QtQuick.Window 2.12

import MainModel 1.0
import SimulationController 1.0
import MediaPlayerModel 1.0
import TellTalesModel 1.0
import NormalModeModel 1.0
import "view" as View

Window {
    id: window;
    width: 800;
    height: 480;
    visible: true
    title: qsTr("Instrument Cluster Demo")
    readonly property real designWidth: 800
    readonly property real designHeight: 480
    readonly property real sceneScale: Math.min(width / designWidth, height / designHeight)

    /*
     * Kết nối SerialReceiver signals → QML Models
     * Đây là cầu nối giữa phần cứng STM32 và Dashboard UI
     * Code này chạy GIỐNG HỆT trên PC host và Raspberry Pi
     */
    Connections {
        target: serialReceiver

        /* Khi phần cứng kết nối, tắt simulation để tránh ghi đè */
        function onConnectedChanged() {
            if (serialReceiver.connected) {
                simulationController.stop()
                MainModel.simulationRunning = false
                console.log("[QML] Hardware connected on port: " + serialReceiver.portName + " - simulation stopped")
            } else {
                console.log("[QML] Hardware disconnected, restarting simulation")
                updateSimulationState()
            }
        }

        /* === Tell-Tales: nút nhấn phần cứng → đèn cảnh báo trên dashboard === */
        function onTurnLeftChanged(active)  { TellTalesModel.turnLeftActive = active;  TellTalesModel.turnLeftBlinking = active; }
        function onTurnRightChanged(active) { TellTalesModel.turnRightActive = active; TellTalesModel.turnRightBlinking = active; }
        function onBeamChanged(active)      { TellTalesModel.beamActive = active; }
        function onHighBeamsChanged(active)  { TellTalesModel.highBeamsActive = active; }
        function onParkedChanged(active)    { TellTalesModel.parkedActive = active; }
        function onAirbagChanged(active)    { TellTalesModel.airbagActive = active; }

        /* === Media Player: nút nhấn phần cứng → điều khiển nhạc === */
        function onMediaPlayToggled()   {
            if (MediaPlayerModel.mediaPlayback) MediaPlayerModel.stop()
            else MediaPlayerModel.play()
        }
        function onMediaNextTriggered() { MediaPlayerModel.nextSong(); }

        /* === Sensor Data: cập nhật speed, rpm từ phần cứng === */
        function onSpeedReceived(speed) {
            MainModel.speed = speed
        }
        function onRpmReceived(rpm)       { MainModel.rpm = rpm }
        function onFuelLevelReceived(level)    { MainModel.fuelLevel = level }
        function onBatteryLevelReceived(level) { MainModel.batteryLevel = level }
        function onGearReceived(gear)     { MainModel.gearShiftText = gear }
    }

    function handleKey(key : int) {
        if (key === Qt.Key_Right) {
            MediaPlayerModel.nextSong()
        } else if (key === Qt.Key_Left) {
            MediaPlayerModel.previousSong()
        } else if (key === Qt.Key_Space) {
            updateSimulationState()
        } else if (key === Qt.Key_Q) {
            TellTalesModel.turnLeftActive = !TellTalesModel.turnLeftActive
        } else if (key === Qt.Key_A) {
            TellTalesModel.turnLeftBlinking = !TellTalesModel.turnLeftBlinking
        } else if (key === Qt.Key_E) {
            TellTalesModel.turnRightActive = !TellTalesModel.turnRightActive
        } else if (key === Qt.Key_D) {
            TellTalesModel.turnRightBlinking = !TellTalesModel.turnRightBlinking
        } else if (key === Qt.Key_W) {
            TellTalesModel.beamActive = !TellTalesModel.beamActive
        } else if (key === Qt.Key_R) {
            TellTalesModel.highBeamsActive = !TellTalesModel.highBeamsActive
        } else if (key === Qt.Key_T) {
            TellTalesModel.parkedActive = !TellTalesModel.parkedActive
        } else if (key === Qt.Key_Y) {
            TellTalesModel.airbagActive = !TellTalesModel.airbagActive
        } else if (key === Qt.Key_U) {
            TellTalesModel.indicatorOpacity = TellTalesModel.indicatorOpacity > 0 ? 0 : 1
        } else if (key === Qt.Key_N) {
            NormalModeModel.nextMenu()
        } else if (key === Qt.Key_M) {
            NormalModeModel.previousMenu()
        }
    }

    function updateSimulationState() {
        if (MainModel.simulationRunning) {
            simulationController.stop()
        } else {
            simulationController.start()
        }
        MainModel.simulationRunning = !MainModel.simulationRunning;
    }

    Keys.onPressed: (event) => {
        handleKey(event.key)
        event.accepted = true
    }

    Shortcut { sequence: "Space"; onActivated: handleKey(Qt.Key_Space) }
    Shortcut { sequence: "Left"; onActivated: handleKey(Qt.Key_Left) }
    Shortcut { sequence: "Right"; onActivated: handleKey(Qt.Key_Right) }
    Shortcut { sequence: "Q"; onActivated: handleKey(Qt.Key_Q) }
    Shortcut { sequence: "A"; onActivated: handleKey(Qt.Key_A) }
    Shortcut { sequence: "E"; onActivated: handleKey(Qt.Key_E) }
    Shortcut { sequence: "D"; onActivated: handleKey(Qt.Key_D) }
    Shortcut { sequence: "W"; onActivated: handleKey(Qt.Key_W) }
    Shortcut { sequence: "R"; onActivated: handleKey(Qt.Key_R) }
    Shortcut { sequence: "T"; onActivated: handleKey(Qt.Key_T) }
    Shortcut { sequence: "Y"; onActivated: handleKey(Qt.Key_Y) }
    Shortcut { sequence: "U"; onActivated: handleKey(Qt.Key_U) }
    Shortcut { sequence: "N"; onActivated: handleKey(Qt.Key_N) }
    Shortcut { sequence: "M"; onActivated: handleKey(Qt.Key_M) }

    Item {
        id: sceneRoot
        width: window.designWidth
        height: window.designHeight
        anchors.centerIn: parent
        transform: Scale {
            origin.x: sceneRoot.width / 2
            origin.y: sceneRoot.height / 2
            xScale: window.sceneScale
            yScale: window.sceneScale
        }

        Rectangle {
            id: root;
            anchors.fill: parent;
            focus: true

            color: "#00091a"

            View.TellTales {
                anchors.horizontalCenter: parent.horizontalCenter;
                y:16;
            }

            View.Car {
                anchors.fill: parent;
            }

            View.NormalMode {
                id: normalMode;
                anchors.fill: parent;
            }

            View.StatusBar {
                anchors.fill: parent;
            }

            SimulationController {
                id: simulationController
            }

            Component.onCompleted: {
                root.forceActiveFocus()
                /* Chỉ start simulation nếu CHƯA có hardware */
                if (!serialReceiver.connected) {
                    updateSimulationState()
                } else {
                    console.log("[QML] Hardware already connected, skipping simulation")
                }
            }
        }
    }
}
