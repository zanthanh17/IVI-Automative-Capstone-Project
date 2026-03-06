import QtQuick 2.12
import Style 1.0
import BluetoothManager 1.0

NormalModeContentItem {
    id: bluetoothRoot

    function rssiColor(rssiValue) {
        if (rssiValue >= -60) {
            return "#68efcc"
        }
        if (rssiValue >= -75) {
            return "#8fc9ff"
        }
        return "#7e90a6"
    }

    /* === Control Buttons === */
    Row {
        id: controlsRow
        anchors.horizontalCenter: parent.horizontalCenter
        y: 112
        width: 320
        spacing: 10

        Rectangle {
            width: (controlsRow.width - controlsRow.spacing * 2) / 3
            height: 26
            radius: 13
            color: BluetoothManager.powered ? "#214f47" : "#4b2430"
            border.width: 1
            border.color: BluetoothManager.powered ? "#66ddc5" : "#ca7386"

            Text {
                anchors.centerIn: parent
                text: BluetoothManager.powered ? "ON" : "OFF"
                color: "#e8f4ff"
                font.pixelSize: 11
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: BluetoothManager.setPowered(!BluetoothManager.powered)
            }
        }

        Rectangle {
            width: (controlsRow.width - controlsRow.spacing * 2) / 3
            height: 26
            radius: 13
            color: BluetoothManager.pairMode ? "#234d76" : "#1b2940"
            border.width: 1
            border.color: BluetoothManager.pairMode ? "#66b2ff" : "#3f6a97"
            opacity: BluetoothManager.powered ? 1.0 : 0.5

            Text {
                anchors.centerIn: parent
                text: BluetoothManager.pairMode ? "Pairing" : "Pair Mode"
                color: "#e8f4ff"
                font.pixelSize: 11
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: BluetoothManager.powered
                onClicked: BluetoothManager.setPairMode(!BluetoothManager.pairMode)
            }
        }

        Rectangle {
            width: (controlsRow.width - controlsRow.spacing * 2) / 3
            height: 26
            radius: 13
            color: BluetoothManager.discovering ? "#27566d" : "#1b2940"
            border.width: 1
            border.color: BluetoothManager.discovering ? "#72c9ff" : "#3f6a97"
            opacity: BluetoothManager.powered ? 1.0 : 0.5

            Text {
                anchors.centerIn: parent
                text: BluetoothManager.discovering ? "Stop" : "Scan"
                color: "#e8f4ff"
                font.pixelSize: 11
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: BluetoothManager.powered
                onClicked: {
                    if (BluetoothManager.discovering) {
                        BluetoothManager.stopDiscovery()
                    } else {
                        BluetoothManager.startDiscovery()
                    }
                }
            }
        }
    }

    /* === Device List === */
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 148
        width: 320
        height: 170
        clip: true

        ListView {
            id: deviceList
            anchors.fill: parent
            clip: true
            model: BluetoothManager.devices

            delegate: Item {
                property var device: modelData
                property bool showRow: device.audioCapable || device.paired || device.connected

                width: deviceList.width
                height: showRow ? 42 : 0
                visible: showRow
                opacity: BluetoothManager.powered ? 1.0 : 0.45

                /* Subtle separator line */
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: "#1a3355"
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: 8

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: device.connected ? "#5af0ce" : (device.paired ? "#6ab5ff" : "#6f8094")
                    }

                    Column {
                        width: 130
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            text: device.name
                            color: Style.lightPeriwinkle
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: device.address + (device.isLastConnected ? "  LAST" : "")
                            color: "#8fa8c1"
                            font.pixelSize: 9
                            elide: Text.ElideMiddle
                            width: parent.width
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: device.rssi + " dBm"
                        color: bluetoothRoot.rssiColor(device.rssi)
                        font.pixelSize: 9
                    }

                    Rectangle {
                        width: device.connected ? 78 : 70
                        height: 24
                        radius: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: device.connected ? "#2b4f4a" : "#1f3857"
                        border.width: 1
                        border.color: device.connected ? "#7de4d2" : "#71b7ff"
                        opacity: device.busy ? 0.55 : 1.0

                        Text {
                            anchors.centerIn: parent
                            text: device.busy
                                  ? "..."
                                  : (device.connected ? "Disconnect" : (device.paired ? "Connect" : "Pair"))
                            color: "#eaf5ff"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: BluetoothManager.powered && !device.busy
                            onClicked: {
                                if (device.connected) {
                                    BluetoothManager.disconnectDevice(device.path)
                                } else if (device.paired) {
                                    BluetoothManager.connectDevice(device.path)
                                } else {
                                    BluetoothManager.pairDevice(device.path)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (device.paired && !device.busy) ? "Forget" : ""
                        color: "#7f9ab3"
                        font.pixelSize: 9

                        MouseArea {
                            anchors.fill: parent
                            enabled: device.paired && !device.busy && BluetoothManager.powered
                            onClicked: BluetoothManager.forgetDevice(device.path)
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: BluetoothManager.refresh()
}
