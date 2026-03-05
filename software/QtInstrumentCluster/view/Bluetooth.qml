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

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: 112
        width: 320
        height: 208
        radius: 14
        color: "#0b1626"
        border.width: 1
        border.color: "#2a5d9a"
        clip: true

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#12365d" }
            GradientStop { position: 0.52; color: "#102b49" }
            GradientStop { position: 1.0; color: "#0a1625" }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#27496a55" }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }

        Row {
            id: controlsRow
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 9
            spacing: 6
            property real buttonWidth: (width - spacing * 2) / 3

            Rectangle {
                width: controlsRow.buttonWidth
                height: 22
                radius: 11
                color: BluetoothManager.powered ? "#214f47" : "#4b2430"
                border.width: 1
                border.color: BluetoothManager.powered ? "#66ddc5" : "#ca7386"

                Text {
                    anchors.centerIn: parent
                    text: BluetoothManager.powered ? "ON" : "OFF"
                    color: "#e8f4ff"
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "Sarabun"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: BluetoothManager.setPowered(!BluetoothManager.powered)
                }
            }

            Rectangle {
                width: controlsRow.buttonWidth
                height: 22
                radius: 11
                color: BluetoothManager.pairMode ? "#234d76" : "#1b2940"
                border.width: 1
                border.color: BluetoothManager.pairMode ? "#66b2ff" : "#3f6a97"
                opacity: BluetoothManager.powered ? 1.0 : 0.5

                Text {
                    anchors.centerIn: parent
                    text: BluetoothManager.pairMode ? "Pairing" : "Pair Mode"
                    color: "#e8f4ff"
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "Sarabun"
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: BluetoothManager.powered
                    onClicked: BluetoothManager.setPairMode(!BluetoothManager.pairMode)
                }
            }

            Rectangle {
                width: controlsRow.buttonWidth
                height: 22
                radius: 11
                color: BluetoothManager.discovering ? "#27566d" : "#1b2940"
                border.width: 1
                border.color: BluetoothManager.discovering ? "#72c9ff" : "#3f6a97"
                opacity: BluetoothManager.powered ? 1.0 : 0.5

                Text {
                    anchors.centerIn: parent
                    text: BluetoothManager.discovering ? "Stop" : "Scan"
                    color: "#e8f4ff"
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "Sarabun"
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

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 40
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            radius: 11
            color: "#101d2d"
            border.width: 1
            border.color: "#2b567d"
            clip: true

            ListView {
                id: deviceList
                anchors.fill: parent
                clip: true
                model: BluetoothManager.devices

                delegate: Rectangle {
                    property var device: modelData
                    property bool showRow: device.audioCapable || device.paired || device.connected

                    width: deviceList.width
                    height: showRow ? 40 : 0
                    visible: showRow
                    color: index % 2 === 0 ? "#162437" : "#142133"
                    opacity: BluetoothManager.powered ? 1.0 : 0.45

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 8
                        spacing: 7

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: device.connected ? "#5af0ce" : (device.paired ? "#6ab5ff" : "#6f8094")
                        }

                        Column {
                            width: 122
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            Text {
                                text: device.name
                                color: "#e6f1ff"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Sarabun"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: device.address + (device.isLastConnected ? "  LAST" : "")
                                color: "#8fa8c1"
                                font.pixelSize: 8
                                font.family: "Sarabun"
                                elide: Text.ElideMiddle
                                width: parent.width
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: device.rssi + " dBm"
                            color: bluetoothRoot.rssiColor(device.rssi)
                            font.pixelSize: 9
                            font.family: "Sarabun"
                        }

                        Rectangle {
                            width: device.connected ? 78 : 70
                            height: 22
                            radius: 11
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
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "Sarabun"
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
                            font.family: "Sarabun"

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
    }

    Component.onCompleted: BluetoothManager.refresh()
}
