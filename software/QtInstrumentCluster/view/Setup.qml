import QtQuick 2.12
import Style 1.0
import NormalModeModel 1.0
import BluetoothManager 1.0
import SystemSettings 1.0

NormalModeContentItem {
    id: setupRoot

    // Local UI state for popups
    property bool wifiPopupOpen: false
    property bool bluetoothPopupOpen: false

    Component.onCompleted: {
        // Đồng bộ trạng thái ban đầu từ controllers hệ thống
        NormalModeModel.bluetoothEnabled = BluetoothManager.powered
        NormalModeModel.wifiEnabled = SystemSettings.wifiEnabled
        NormalModeModel.volumeLevel = SystemSettings.volumeLevel
        NormalModeModel.brightnessLevel = SystemSettings.brightnessLevel
    }

    Connections {
        target: BluetoothManager
        onPoweredChanged: {
            NormalModeModel.bluetoothEnabled = BluetoothManager.powered
        }
    }

    Connections {
        target: SystemSettings
        onWifiEnabledChanged: {
            NormalModeModel.wifiEnabled = SystemSettings.wifiEnabled
        }
        onVolumeLevelChanged: {
            NormalModeModel.volumeLevel = SystemSettings.volumeLevel
        }
        onBrightnessLevelChanged: {
            NormalModeModel.brightnessLevel = SystemSettings.brightnessLevel
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 28

        // Quick controls master toggle
        Row {
            spacing: 10
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                id: quickToggle
                source: "qrc:/images/others/quick controls.svg"
                width: 26
                height: 26
                fillMode: Image.PreserveAspectFit
                opacity: NormalModeModel.quickControlsEnabled ? 1.0 : 0.4

                MouseArea {
                    anchors.fill: parent
                    onClicked: NormalModeModel.quickControlsEnabled = !NormalModeModel.quickControlsEnabled
                }
            }

            Column {
                spacing: 2
                Text {
                    text: "Quick controls"
                    color: Style.textPrimary
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    text: NormalModeModel.quickControlsEnabled ? "Visible on status bar" : "Hidden from status bar"
                    color: Style.textSecondary
                    font.pixelSize: 11
                }
            }
        }

        // Connectivity toggles
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24

            Rectangle {
                width: 120
                height: 42
                radius: 18
                color: NormalModeModel.wifiEnabled ? Style.brightBlue : Style.backgroundPanelSoft

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Image {
                        source: "qrc:/images/others/wifi.png"
                        width: 18; height: 18
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        text: "Wi‑Fi"
                        color: NormalModeModel.wifiEnabled ? Style.textPrimary : Style.textSecondary
                        font.pixelSize: 14
                    }
                    // Small arrow when enabled to hint more settings
                    Text {
                        visible: NormalModeModel.wifiEnabled
                        text: "\u203A"   // single right-pointing angle quote
                        color: Style.textPrimary
                        font.pixelSize: 16
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!NormalModeModel.wifiEnabled) {
                            NormalModeModel.wifiEnabled = true
                            SystemSettings.wifiEnabled = true
                        } else {
                            setupRoot.wifiPopupOpen = true
                        }
                    }
                }
            }

            Rectangle {
                width: 140
                height: 42
                radius: 18
                color: NormalModeModel.bluetoothEnabled ? Style.brightBlue : Style.backgroundPanelSoft

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Image {
                        source: "qrc:/images/others/bluetooth.svg"
                        width: 18; height: 18
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        text: "Bluetooth"
                        color: NormalModeModel.bluetoothEnabled ? Style.textPrimary : Style.textSecondary
                        font.pixelSize: 14
                    }
                    Text {
                        visible: NormalModeModel.bluetoothEnabled
                        text: "\u203A"
                        color: Style.textPrimary
                        font.pixelSize: 16
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!NormalModeModel.bluetoothEnabled) {
                            NormalModeModel.bluetoothEnabled = true
                            BluetoothManager.setPowered(true)
                        } else {
                            setupRoot.bluetoothPopupOpen = true
                        }
                    }
                }
            }
        }

        // Sliders: volume & brightness (custom, không dùng QtQuick.Controls)
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Row {
                spacing: 10
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: "qrc:/images/others/volume.svg"
                    width: 18; height: 18
                    fillMode: Image.PreserveAspectFit
                }

                Rectangle {
                    id: volumeTrack
                    width: 220
                    height: 4
                    radius: 2
                    color: "#ffffff30"

                    Rectangle {
                        width: NormalModeModel.volumeLevel * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Style.brightBlue
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: if (pressed) {
                            var v = (mouse.x / volumeTrack.width)
                            NormalModeModel.volumeLevel = Math.max(0, Math.min(1, v))
                            SystemSettings.volumeLevel = NormalModeModel.volumeLevel
                        }
                        onPressed: {
                            var v = (mouse.x / volumeTrack.width)
                            NormalModeModel.volumeLevel = Math.max(0, Math.min(1, v))
                            SystemSettings.volumeLevel = NormalModeModel.volumeLevel
                        }
                    }
                }
            }

            Row {
                spacing: 10
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    source: "qrc:/images/others/brightness.svg"
                    width: 18; height: 18
                    fillMode: Image.PreserveAspectFit
                }

                Rectangle {
                    id: brightnessTrack
                    width: 220
                    height: 4
                    radius: 2
                    color: "#ffffff30"

                    Rectangle {
                        width: NormalModeModel.brightnessLevel * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Style.brightBlue
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: if (pressed) {
                            var v = (mouse.x / brightnessTrack.width)
                            NormalModeModel.brightnessLevel = Math.max(0, Math.min(1, v))
                            SystemSettings.brightnessLevel = NormalModeModel.brightnessLevel
                        }
                        onPressed: {
                            var v = (mouse.x / brightnessTrack.width)
                            NormalModeModel.brightnessLevel = Math.max(0, Math.min(1, v))
                            SystemSettings.brightnessLevel = NormalModeModel.brightnessLevel
                        }
                    }
                }
            }
        }
    }

    // === Wi‑Fi settings overlay ===
    Rectangle {
        id: wifiPopup
        anchors.fill: parent
        color: "#00000080"
        visible: wifiPopupOpen
        z: 50

        Rectangle {
            width: 360
            height: 260
            radius: 22
            color: Style.backgroundPanelSoft
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 16

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 10

                    // Back icon
                    Image {
                        id: wifiBack
                        source: "qrc:/images/others/back.png"
                        width: 20
                        height: 20
                        fillMode: Image.PreserveAspectFit

                        MouseArea {
                            anchors.fill: parent
                            onClicked: wifiPopupOpen = false
                        }
                    }

                    // Title + subtitle
                    Column {
                        spacing: 2
                        Text {
                            text: "Wi‑Fi networks"
                            color: Style.textPrimary
                            font.pixelSize: 16
                            font.bold: true
                        }
                        Text {
                            text: "Select a network to connect"
                            color: Style.textSecondary
                            font.pixelSize: 11
                        }
                    }
                }

                ListView {
                    id: wifiList
                    model: ListModel {
                        ListElement { ssid: "Home Wi‑Fi"; strength: "•••"; secured: true }
                        ListElement { ssid: "Office"; strength: "•••"; secured: true }
                        ListElement { ssid: "Guest"; strength: "••"; secured: false }
                    }
                    clip: true
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 4
                    anchors.bottom: parent.bottom

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 34
                        radius: 10
                        color: hovered ? "#ffffff10" : "transparent"

                        property bool hovered: false

                        Row {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 10

                            Text {
                                text: ssid
                                color: Style.textPrimary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignLeft
                            }

                            Text {
                                text: strength
                                color: Style.textSecondary
                                font.pixelSize: 12
                            }

                            Text {
                                text: secured ? "lock" : ""
                                color: Style.textSecondary
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.hovered = true
                            onExited: parent.hovered = false
                            onClicked: {
                                // TODO: trigger backend connect using ssid
                                wifiPopupOpen = false
                            }
                        }
                    }
                }
            }
        }
    }

    // === Bluetooth settings overlay ===
    Rectangle {
        id: bluetoothPopup
        anchors.fill: parent
        color: "#00000080"
        visible: bluetoothPopupOpen
        z: 50

        Rectangle {
            width: 320
            height: 220
            radius: 22
            color: Style.backgroundPanelSoft
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 16

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 10

                    Image {
                        id: btBack
                        source: "qrc:/images/others/back.png"
                        width: 20
                        height: 20
                        fillMode: Image.PreserveAspectFit

                        MouseArea {
                            anchors.fill: parent
                            onClicked: bluetoothPopupOpen = false
                        }
                    }

                    Column {
                        spacing: 2
                        Text {
                            text: "Bluetooth devices"
                            color: Style.textPrimary
                            font.pixelSize: 16
                            font.bold: true
                        }
                        Text {
                            text: "Manage paired devices from Pi"
                            color: Style.textSecondary
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    text: "Pairing logic will be handled by the Pi backend."
                    color: Style.textSecondary
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}

