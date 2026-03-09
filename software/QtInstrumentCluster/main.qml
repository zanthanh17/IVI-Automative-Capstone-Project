import QtQuick 2.12
import QtQuick.Window 2.12

import MainModel 1.0
import MediaPlayerModel 1.0
import TellTalesModel 1.0
import NormalModeModel 1.0
import Style 1.0
import "view" as View

Window {
    id: window;
    width: 1024;
    height: 600;
    visible: true
    title: qsTr("Instrument Cluster Demo")
    readonly property real designWidth: 1024
    readonly property real designHeight: 600
    readonly property real sceneScale: Math.min(width / designWidth, height / designHeight)

    /*
     * Kết nối SerialReceiver signals → QML Models
     * Đây là cầu nối giữa phần cứng STM32 và Dashboard UI
     * Code này chạy GIỐNG HỆT trên PC host và Raspberry Pi
     */
    Connections {
        target: serialReceiver

        /* Khi phần cứng kết nối, log trạng thái */
        function onConnectedChanged() {
            if (serialReceiver.connected) {
                console.log("[QML] Hardware connected on port: " + serialReceiver.portName)
            } else {
                console.log("[QML] Hardware disconnected")
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
            id: root
            anchors.fill: parent
            focus: true
            color: Style.backgroundBase

            Keys.onPressed: (event) => {
                window.handleKey(event.key)
                event.accepted = true
            }

            View.NormalMode {
                id: normalMode;
                anchors.fill: parent;
                z: 1
            }

            View.Car {
                x: normalMode.leftPaneX
                y: normalMode.leftPaneY
                width: normalMode.leftPaneWidth
                height: normalMode.leftPaneHeight
                bottomInset: normalMode.vehicleBottomInset
                centerOffsetX: normalMode.vehicleCenterOffsetX
                carScale: 1.0
                z: 10
            }

            View.TellTales {
                x: (root.width - width) / 2
                y: normalMode.topPaneY + (normalMode.topPaneHeight - height) / 2
                z: 10
            }

            View.StatusBar {
                x: normalMode.leftPaneX
                y: normalMode.leftPaneY
                width: normalMode.leftPaneWidth
                height: normalMode.leftPaneHeight
                z: 10
            }

            // Quick controls status icons (wifi / bt / volume / brightness)
            Row {
                id: quickStatusRow
                spacing: 12
                anchors.top: root.top
                anchors.topMargin: 18
                anchors.right: root.right
                anchors.rightMargin: 32
                visible: NormalModeModel.quickControlsEnabled
                opacity: 0.9
                z: 20

                Image {
                    source: "qrc:/images/others/wifi.png"
                    width: 18
                    height: 18
                    visible: NormalModeModel.wifiEnabled
                    fillMode: Image.PreserveAspectFit
                }

                Image {
                    source: "qrc:/images/others/bluetooth.svg"
                    width: 18
                    height: 18
                    visible: NormalModeModel.bluetoothEnabled
                    fillMode: Image.PreserveAspectFit
                }

                Image {
                    source: "qrc:/images/others/volume.svg"
                    width: 18
                    height: 18
                    fillMode: Image.PreserveAspectFit
                }

                Image {
                    source: "qrc:/images/others/brightness.svg"
                    width: 18
                    height: 18
                    fillMode: Image.PreserveAspectFit
                }
            }

            Component.onCompleted: {
                root.forceActiveFocus()
                if (serialReceiver.connected) {
                    console.log("[QML] Hardware already connected")
                } else {
                    console.log("[QML] No hardware detected, waiting for connection...")
                }
            }
        }
    }
}
