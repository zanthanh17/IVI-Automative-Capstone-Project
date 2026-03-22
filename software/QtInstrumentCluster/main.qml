import QtQuick 2.12
import QtQuick.Window 2.12

import MainModel 1.0
import MediaPlayerModel 1.0
import TellTalesModel 1.0
import NormalModeModel 1.0
import SystemSettings 1.0
import Style 1.0
import "view" as View

Window {
    id: window;
    width: 1024;
    height: 600;
    visible: true
    title: qsTr("Instrument Cluster Demo")
    visibility: Window.FullScreen
    readonly property real designWidth: 1024
    readonly property real designHeight: 600
    readonly property real sceneScale: Math.min(width / designWidth, height / designHeight)
    readonly property string virtualKeyboardLocale: (virtualKeyboardLocaleFromEnv && virtualKeyboardLocaleFromEnv.length > 0)
                                                  ? virtualKeyboardLocaleFromEnv
                                                  : "vi_VN"

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
            color: "transparent"
            property date currentDateTime: new Date()

            Keys.onPressed: (event) => {
                window.handleKey(event.key)
                event.accepted = true
            }

            Image {
                id: bgImage
                anchors.fill: parent
                source: "qrc:/images/background/bg_car2.png"
                fillMode: Image.PreserveAspectCrop
                z: -2
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

            Item {
                id: topBar
                anchors.top: root.top
                anchors.topMargin: 16
                anchors.left: root.left
                anchors.right: root.right
                height: 32
                z: 20

                Timer {
                    interval: 1000; repeat: true; running: true; triggeredOnStart: true
                    onTriggered: root.currentDateTime = new Date()
                }

                Image {
                    id: topLogo
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.verticalCenter: parent.verticalCenter
                    source: "qrc:/images/Tesla_Logo.png"
                    sourceSize.width: 32
                    sourceSize.height: 32
                    fillMode: Image.PreserveAspectFit
                    opacity: 0.9
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Text {
                            text: Qt.formatDateTime(root.currentDateTime, "h:mm")
                            color: "#ffffff"
                            font.pixelSize: 28
                            font.bold: true
                            font.letterSpacing: 1
                        }
                        Text {
                            anchors.baseline: parent.children[0].baseline
                            text: Qt.formatDateTime(root.currentDateTime, "ap")
                            color: "#ffffff"
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(root.currentDateTime, "dddd | MMMM d, yyyy")
                        color: "#dcdce0"
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 0.5
                    }
                }

                MouseArea {
                    anchors.fill: quickStatusRow
                    anchors.margins: -10
                    onClicked: {
                        SystemSettings.launchDrowsyCamera()
                        cameraView.visible = true
                    }
                }

                Row {
                    id: quickStatusRow
                    spacing: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: 0.9

                    Image {
                        source: "qrc:/images/menu/camera.png"
                        width: 24
                        height: 24
                        sourceSize.width: 24
                        sourceSize.height: 24
                        fillMode: Image.PreserveAspectFit
                    }
                }
            }

            View.StatusBar {
                x: normalMode.leftPaneX
                y: normalMode.leftPaneY
                width: normalMode.leftPaneWidth
                height: normalMode.leftPaneHeight
                z: 10
            }

            View.TellTales {
                x: normalMode.leftPaneX + (normalMode.leftPaneWidth - width) / 2
                y: normalMode.leftPaneY + 16
                z: 11
            }

            View.CameraView {
                id: cameraView
                anchors.fill: parent
                z: 100
                visible: false
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

    Loader {
        id: virtualKeyboardLoader
        anchors.fill: parent
        z: 1000
        source: "qrc:/view/VirtualKeyboardOverlay.qml"

        onLoaded: {
            if (item && item.keyboardLocale !== undefined) {
                item.keyboardLocale = window.virtualKeyboardLocale
            }
        }

        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[QML] Qt Virtual Keyboard module is not installed. Text boxes will use hardware keyboard only.")
            }
        }
    }

    Rectangle {
        id: dimmingOverlay
        anchors.fill: parent
        color: "black"
        opacity: 1.0 - SystemSettings.brightnessLevel
        z: 9998
        enabled: false // Let touches pass through
    }
}
