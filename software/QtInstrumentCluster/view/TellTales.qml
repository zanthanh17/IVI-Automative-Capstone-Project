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
            activeColor: "#2dff89"
            active: TellTalesModel.turnLeftActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
            blinking: TellTalesModel.turnLeftBlinking
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/beam.png"
            activeColor: "#2dff89"
            active: TellTalesModel.beamActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/high-beams.png"
            activeColor: "#37a0ff"
            active: TellTalesModel.highBeamsActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
    }

    Rectangle {
        id: centerClock
        anchors.centerIn: parent
        width: 220
        height: 52
        radius: 24
        color: Style.backgroundPanelSoft
        border.width: 1
        border.color: Style.brightBlue
        opacity: 0.9

        Column {
            anchors.centerIn: parent
            spacing: 2
            
            Text {
                id: clockTime
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(telltales.currentDateTime, "hh:mm")
                color: "#ffffff"
                font.pixelSize: 22
                font.bold: true
                font.letterSpacing: 1
            }

            Text {
                id: clockDate
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(telltales.currentDateTime, "ddd, dd MMM yyyy").toUpperCase()
                color: "#8aa6c1"
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
            }
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
            activeColor: "#ff4e5f"
            active: TellTalesModel.parkedActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/airbag.png"
            activeColor: "#ff4e5f"
            active: TellTalesModel.airbagActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/turn_right.png"
            activeColor: "#2dff89"
            active: TellTalesModel.turnRightActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
            blinking: TellTalesModel.turnRightBlinking
        }
    }
}
