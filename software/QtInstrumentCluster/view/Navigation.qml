import QtQuick 2.12
import Style 1.0
import NavigationModel 1.0
import NormalModeModel 1.0

NormalModeContentItem {
    id: navRoot

    /* === Current Street (top) === */
    Text {
        id: currentStreetLabel
        anchors.horizontalCenter: parent.horizontalCenter
        y: 95
        text: NavigationModel.currentStreet
        font.pixelSize: 13
        font.family: "Sarabun"
        color: "#657080"
        opacity: 0.8
    }

    /* === Maneuver Arrow (center) === */
    Canvas {
        id: arrowCanvas
        anchors.horizontalCenter: parent.horizontalCenter
        y: 125
        width: 80
        height: 80

        property int maneuver: NavigationModel.maneuver
        onManeuverChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            var cx = width / 2
            var cy = height / 2

            ctx.lineWidth = 3
            ctx.strokeStyle = Style.brightBlue
            ctx.fillStyle = Style.brightBlue
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            if (maneuver === NavigationModel.TurnRight) {
                // Shaft going up then right
                ctx.beginPath()
                ctx.moveTo(cx - 10, cy + 25)
                ctx.lineTo(cx - 10, cy - 5)
                ctx.lineTo(cx + 20, cy - 5)
                ctx.stroke()
                // Arrowhead pointing right
                ctx.beginPath()
                ctx.moveTo(cx + 10, cy - 20)
                ctx.lineTo(cx + 30, cy - 5)
                ctx.lineTo(cx + 10, cy + 10)
                ctx.fill()
            }
            else if (maneuver === NavigationModel.TurnLeft) {
                // Shaft going up then left
                ctx.beginPath()
                ctx.moveTo(cx + 10, cy + 25)
                ctx.lineTo(cx + 10, cy - 5)
                ctx.lineTo(cx - 20, cy - 5)
                ctx.stroke()
                // Arrowhead pointing left
                ctx.beginPath()
                ctx.moveTo(cx - 10, cy - 20)
                ctx.lineTo(cx - 30, cy - 5)
                ctx.lineTo(cx - 10, cy + 10)
                ctx.fill()
            }
            else if (maneuver === NavigationModel.GoStraight) {
                // Shaft going up
                ctx.beginPath()
                ctx.moveTo(cx, cy + 25)
                ctx.lineTo(cx, cy - 15)
                ctx.stroke()
                // Arrowhead pointing up
                ctx.beginPath()
                ctx.moveTo(cx - 15, cy - 5)
                ctx.lineTo(cx, cy - 28)
                ctx.lineTo(cx + 15, cy - 5)
                ctx.fill()
            }
            else if (maneuver === NavigationModel.UTurn) {
                // U-turn shaft
                ctx.beginPath()
                ctx.moveTo(cx + 12, cy + 25)
                ctx.lineTo(cx + 12, cy - 10)
                ctx.arc(cx, cy - 10, 12, 0, Math.PI, true)
                ctx.lineTo(cx - 12, cy + 5)
                ctx.stroke()
                // Arrowhead pointing down
                ctx.beginPath()
                ctx.moveTo(cx - 24, cy - 5)
                ctx.lineTo(cx - 12, cy + 12)
                ctx.lineTo(cx, cy - 5)
                ctx.fill()
            }
            else if (maneuver === NavigationModel.Arrive) {
                // Destination pin
                ctx.beginPath()
                ctx.arc(cx, cy - 8, 16, 0, Math.PI * 2)
                ctx.stroke()
                // Pin dot
                ctx.beginPath()
                ctx.arc(cx, cy - 8, 6, 0, Math.PI * 2)
                ctx.fill()
                // Pin stem
                ctx.beginPath()
                ctx.moveTo(cx, cy + 8)
                ctx.lineTo(cx, cy + 25)
                ctx.stroke()
            }
        }

        /* Subtle glow pulse when active */
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.6; duration: 1200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.6; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
        }
    }

    /* === Distance to next turn === */
    Text {
        id: distanceText
        anchors.horizontalCenter: parent.horizontalCenter
        y: 213
        text: NavigationModel.distanceToTurnText
        font.pixelSize: 26
        font.bold: true
        font.family: "Sarabun"
        color: Style.lightPeriwinkle

        Behavior on text {
            enabled: false  // text cannot animate, but opacity can
        }
    }

    /* === Next street name === */
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 248
        spacing: 6

        Text {
            text: "→"
            font.pixelSize: 14
            font.family: "Sarabun"
            color: Style.brightBlue
        }
        Text {
            text: NavigationModel.nextStreet
            font.pixelSize: 14
            font.family: "Sarabun"
            color: Style.lightPeriwinkle
        }
    }

    /* === ETA & Total Distance (bottom) === */
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 278
        spacing: 20

        Row {
            spacing: 4
            Text {
                text: "ETA"
                font.pixelSize: 11
                font.family: "Sarabun"
                color: "#657080"
            }
            Text {
                text: NavigationModel.eta
                font.pixelSize: 13
                font.bold: true
                font.family: "Sarabun"
                color: Style.lightPeriwinkle
            }
        }

        // Separator dot
        Text {
            text: "·"
            font.pixelSize: 14
            font.family: "Sarabun"
            color: "#657080"
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            spacing: 4
            Text {
                text: "DIST"
                font.pixelSize: 11
                font.family: "Sarabun"
                color: "#657080"
            }
            Text {
                text: NavigationModel.totalDistance
                font.pixelSize: 13
                font.bold: true
                font.family: "Sarabun"
                color: Style.lightPeriwinkle
            }
        }
    }

    /* === No Navigation active state === */
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 20
        visible: !NavigationModel.active
        text: "No Route Active"
        font.pixelSize: 16
        font.family: "Sarabun"
        color: "#657080"
        opacity: 0.6
    }
}
