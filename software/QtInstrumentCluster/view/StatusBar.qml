import QtQuick 2.12
import Units 1.0
import MainModel 1.0
import Style 1.0

Item {
    id: root
    readonly property real bottomRowMargin: 18
    readonly property string activeGear: {
        var gear = MainModel.normalizeGear(MainModel.gearShiftText)
        if (gear !== "")
            return gear
        return "P"
    }

    Row {
        anchors.top: parent.top
        anchors.topMargin: 72
        anchors.left: parent.left
        anchors.leftMargin: 48
        spacing: 6

        Text {
            anchors.baseline: odoValueText.baseline
            text: "ODO"
            color: Style.textSecondary
            font.pixelSize: 12
        }
        Text {
            id: odoValueText
            text: Units.toInt(Units.kilometersToLongDistanceUnit(Math.max(MainModel.odo, 0)))
            color: Style.textPrimary
            font.pixelSize: 18
            font.bold: true
        }
        Text {
            anchors.baseline: odoValueText.baseline
            text: Units.longDistanceUnit
            color: Style.textSecondary
            font.pixelSize: 12
        }
    }

    Row {
        anchors.top: parent.top
        anchors.topMargin: 72
        anchors.right: parent.right
        anchors.rightMargin: 48
        spacing: 6

        Text {
            anchors.baseline: rangeValueText.baseline
            text: "RANGE"
            color: Style.textSecondary
            font.pixelSize: 12
        }
        Text {
            id: rangeValueText
            text: Units.toInt(Units.kilometersToLongDistanceUnit(Math.max(MainModel.range, 0)))
            color: Style.textPrimary
            font.pixelSize: 18
            font.bold: true
        }
        Text {
            anchors.baseline: rangeValueText.baseline
            text: Units.longDistanceUnit
            color: Style.textSecondary
            font.pixelSize: 12
        }
    }

    LinearGauge {
        id: fuelGauge
        anchors.verticalCenter: gearSelector.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 18
        image: "qrc:/images/status/fuel.png";
        emptyText: "R";
        value: MainModel.fuelLevel;
    }

    LinearGauge {
        id: batteryGauge
        anchors.verticalCenter: gearSelector.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 18
        image: "qrc:/images/status/battery.png";
        emptyText: "E";
        value: MainModel.batteryLevel;
    }

    Rectangle {
        id: gearSelector
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomRowMargin
        width: 200
        height: 36
        radius: 18
        color: Style.backgroundPanelSoft
        border.color: Style.backgroundPanel
        border.width: 1

        readonly property var gears: ["R", "P", "N", "D"]
        readonly property real segmentSpacing: 4
        readonly property real segmentWidth: (width - 6 - segmentSpacing * 3) / 4

        Row {
            anchors.fill: parent
            anchors.margins: 3
            spacing: gearSelector.segmentSpacing

            Repeater {
                model: gearSelector.gears
                delegate: Rectangle {
                    property string gearText: modelData
                    width: gearSelector.segmentWidth
                    height: parent.height
                    radius: 14
                    color: root.activeGear === gearText ? Style.brightBlue : "transparent"
                    border.width: 0

                    Text {
                        anchors.centerIn: parent
                        text: parent.gearText
                        color: root.activeGear === parent.gearText ? Style.backgroundBase : Style.textSecondary
                        font.pixelSize: 16
                        font.bold: true
                    }
                }
            }
        }
    }
}
