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
        width: 220
        height: 52
        radius: 26  // Pill shape
        
        // Glassmorphism effect: deep gradient with a subtle, thin glowing border
        color: "#200a1526"
        border.width: 1
        border.color: "#406a9bc5"

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#301b3f66" }
            GradientStop { position: 1.0; color: "#500a1526" }
        }

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
