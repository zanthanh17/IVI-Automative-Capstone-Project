import QtQuick 2.12
import TellTalesModel 1.0
import Style 1.0

Item {
    id: telltales
    width: 460
    height: 44

    property date currentDateTime: new Date()

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: telltales.currentDateTime = new Date()
    }

    Row {
        id: leftIndicators
        anchors.right: centerClock.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        TellTalesIndicator {
            source: "qrc:/images/telltales/turn_left.png"
            activeColor: Style.highlighterGreen
            active: TellTalesModel.turnLeftActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
            blinking: TellTalesModel.turnLeftBlinking
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/beam.png"
            activeColor: Style.highlighterGreen
            active: TellTalesModel.beamActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/high-beams.png"
            activeColor: Style.brightBlue
            active: TellTalesModel.highBeamsActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
    }

    Rectangle {
        id: centerClock
        anchors.centerIn: parent
        width: 190
        height: 42
        radius: 12
        color: "#0b1d33d8"
        border.width: 1
        border.color: "#3a79c580"

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1b3f66cc" }
            GradientStop { position: 1.0; color: "#0a1526cc" }
        }

        Text {
            id: clockTime
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 3
            text: Qt.formatDateTime(telltales.currentDateTime, "hh:mm")
            color: Style.lightPeriwinkle
            font.pixelSize: 16
            font.bold: true
            font.family: "Sarabun"
        }

        Text {
            id: clockDate
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: clockTime.bottom
            anchors.topMargin: -1
            text: Qt.formatDateTime(telltales.currentDateTime, "ddd, dd MMM yyyy")
            color: "#9bb5cf"
            font.pixelSize: 9
            font.family: "Sarabun"
        }
    }

    Row {
        id: rightIndicators
        anchors.left: centerClock.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        TellTalesIndicator {
            source: "qrc:/images/telltales/parked.png"
            activeColor: Style.highlighterRed
            active: TellTalesModel.parkedActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/airbag.png"
            activeColor: Style.highlighterRed
            active: TellTalesModel.airbagActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/turn_right.png"
            activeColor: Style.highlighterGreen
            active: TellTalesModel.turnRightActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
            blinking: TellTalesModel.turnRightBlinking
        }
    }
}
