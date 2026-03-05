import QtQuick 2.12
import Style 1.0
import NavigationModel 1.0
import NavigationFeed 1.0

Item {
    id: navRoot

    function maneuverHint(value) {
        if (value === NavigationModel.TurnLeft) {
            return "Turn left"
        }
        if (value === NavigationModel.TurnRight) {
            return "Turn right"
        }
        if (value === NavigationModel.GoStraight) {
            return "Go straight"
        }
        if (value === NavigationModel.UTurn) {
            return "Make a U-turn"
        }
        return "Arrive at destination"
    }

    Rectangle {
        id: hudShell
        anchors.horizontalCenter: parent.horizontalCenter
        y: 82
        width: 392
        height: 286
        radius: 18
        color: "#0a1322"
        border.width: 1
        border.color: "#2f70be"
        clip: true

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#183a5e" }
            GradientStop { position: 0.50; color: "#102c49" }
            GradientStop { position: 1.0; color: "#091625" }
        }

        Canvas {
            id: fallbackMapArt
            anchors.fill: parent
            anchors.margins: 1

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                ctx.fillStyle = "#0f1b2e"
                ctx.fillRect(0, 0, width, height)

                ctx.strokeStyle = "rgba(112,149,191,0.20)"
                ctx.lineWidth = 2
                for (var i = -40; i < width + 80; i += 34) {
                    ctx.beginPath()
                    ctx.moveTo(i, 0)
                    ctx.lineTo(i - 56, height)
                    ctx.stroke()
                }
                for (var j = 20; j < height; j += 36) {
                    ctx.beginPath()
                    ctx.moveTo(0, j)
                    ctx.lineTo(width, j + 22)
                    ctx.stroke()
                }

                var routeX = width * 0.52
                ctx.strokeStyle = "#24394d"
                ctx.lineWidth = 14
                ctx.beginPath()
                ctx.moveTo(routeX, height - 20)
                ctx.lineTo(routeX, height * 0.56)
                ctx.lineTo(routeX - 76, height * 0.56)
                ctx.lineTo(routeX - 128, height * 0.40)
                ctx.stroke()

                ctx.strokeStyle = "#4ff2d5"
                ctx.lineWidth = 8
                ctx.beginPath()
                ctx.moveTo(routeX, height - 20)
                ctx.lineTo(routeX, height * 0.56)
                ctx.lineTo(routeX - 76, height * 0.56)
                ctx.lineTo(routeX - 128, height * 0.40)
                ctx.stroke()
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#102138"
            opacity: 0.22
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.00, 0.01, 0.03, 0.33) }
                GradientStop { position: 0.62; color: Qt.rgba(0.00, 0.01, 0.03, 0.03) }
                GradientStop { position: 1.0; color: Qt.rgba(0.00, 0.01, 0.03, 0.35) }
            }
        }

        Rectangle {
            id: instructionCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.topMargin: 12
            height: 68
            radius: 14
            color: "#1d2737"
            border.width: 1
            border.color: "#2f79ca"
            opacity: 0.96

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Item {
                    width: 36
                    height: parent.height

                    Canvas {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.lineWidth = 3
                            ctx.strokeStyle = "#58f1d4"
                            ctx.fillStyle = "#58f1d4"
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            var m = NavigationModel.maneuver
                            if (m === NavigationModel.TurnRight) {
                                ctx.beginPath()
                                ctx.moveTo(4, 28)
                                ctx.lineTo(4, 10)
                                ctx.lineTo(22, 10)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(15, 3)
                                ctx.lineTo(27, 10)
                                ctx.lineTo(15, 18)
                                ctx.fill()
                            } else if (m === NavigationModel.TurnLeft) {
                                ctx.beginPath()
                                ctx.moveTo(26, 28)
                                ctx.lineTo(26, 10)
                                ctx.lineTo(8, 10)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(15, 3)
                                ctx.lineTo(3, 10)
                                ctx.lineTo(15, 18)
                                ctx.fill()
                            } else if (m === NavigationModel.UTurn) {
                                ctx.beginPath()
                                ctx.moveTo(19, 28)
                                ctx.lineTo(19, 9)
                                ctx.arc(12, 9, 7, 0, Math.PI, true)
                                ctx.lineTo(5, 16)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(2, 10)
                                ctx.lineTo(8, 17)
                                ctx.lineTo(14, 10)
                                ctx.fill()
                            } else if (m === NavigationModel.Arrive) {
                                ctx.beginPath()
                                ctx.arc(15, 11, 7, 0, Math.PI * 2)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.arc(15, 11, 3, 0, Math.PI * 2)
                                ctx.fill()
                            } else {
                                ctx.beginPath()
                                ctx.moveTo(15, 27)
                                ctx.lineTo(15, 7)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(7, 14)
                                ctx.lineTo(15, 3)
                                ctx.lineTo(23, 14)
                                ctx.fill()
                            }
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: NavigationModel.distanceToTurnText
                        color: "#edf6ff"
                        font.pixelSize: 32
                        font.bold: true
                        font.family: "Sarabun"
                    }

                    Text {
                        width: 250
                        text: "In " + NavigationModel.distanceToTurnText + " " + navRoot.maneuverHint(NavigationModel.maneuver).toLowerCase()
                        color: "#9eb3c8"
                        font.pixelSize: 12
                        font.family: "Sarabun"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle {
            id: tripCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            height: 54
            radius: 13
            color: "#1d2737"
            border.width: 1
            border.color: "#2f79ca"
            opacity: 0.96

            Row {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Column {
                    width: 210
                    spacing: 2

                    Text {
                        width: parent.width
                        text: NavigationModel.nextStreet.length > 0 ? NavigationModel.nextStreet : "No destination"
                        color: "#e6f1ff"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: "Sarabun"
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: 12

                        Text {
                            text: NavigationModel.totalDistance
                            color: "#99b4cf"
                            font.pixelSize: 10
                            font.family: "Sarabun"
                        }

                        Text {
                            text: "ETA " + NavigationModel.eta
                            color: "#99b4cf"
                            font.pixelSize: 10
                            font.family: "Sarabun"
                        }
                    }
                }

                Rectangle {
                    width: 92
                    height: 30
                    radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    color: NavigationModel.active ? "#2a4d48" : "#43d9b8"
                    border.width: 1
                    border.color: NavigationModel.active ? "#79d7c8" : "#6ff2d7"

                    Text {
                        anchors.centerIn: parent
                        text: NavigationModel.active ? "Guiding" : "Start"
                        color: NavigationModel.active ? "#bdeee5" : "#07211f"
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "Sarabun"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!NavigationModel.active) {
                                NavigationModel.resetRouteProgress()
                                NavigationModel.active = true
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 372
        text: "QtLocation unavailable - using navigation HUD fallback"
        font.pixelSize: 10
        font.family: "Sarabun"
        color: Style.brightBlue
        opacity: 0.78
    }
}
