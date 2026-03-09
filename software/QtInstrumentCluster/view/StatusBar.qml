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

    Text {
        id: odo
        anchors.top: parent.top
        anchors.topMargin: 32
        anchors.left: parent.left;
        anchors.leftMargin: 38
        text: "ODO"
        color: Style.textSecondary
        font.pixelSize: 12
    }

    Text {
        id: odoValue
        anchors.baseline: odo.baseline;
        anchors.left: odo.right;
        anchors.leftMargin: 4;
        text: Units.toInt(Units.kilometersToLongDistanceUnit(Math.max(MainModel.odo, 0)))
        color: Style.textPrimary
        font.pixelSize: 20
    }

    Text {
        id: odoUnit
        anchors.baseline: odo.baseline;
        anchors.left: odoValue.right;
        anchors.leftMargin: 4;
        text: Units.longDistanceUnit
        color: Style.textSecondary
        font.pixelSize: 12
    }

    Text {
        id: range
        anchors.top: parent.top
        anchors.topMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 116
        text: "RANGE"
        color: Style.textSecondary
        font.pixelSize: 12
    }

    Text {
        id: rangeValue
        anchors.baseline: range.baseline;
        anchors.left: range.right;
        anchors.leftMargin: 4;
        text: Units.toInt(Units.kilometersToLongDistanceUnit(Math.max(MainModel.range, 0)))
        color: Style.textPrimary
        font.pixelSize: 20
    }

    Text {
        id: rangeUnit
        anchors.baseline: range.baseline;
        anchors.left: rangeValue.right;
        anchors.leftMargin: 4;
        text: Units.longDistanceUnit
        color: Style.textSecondary
        font.pixelSize: 12
    }

    Image {
        id: teslaLogo
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: odoValue.verticalCenter
        source: "qrc:/images/Tesla_Logo.png"
        sourceSize.width: 26
        sourceSize.height: 26
        fillMode: Image.PreserveAspectFit
        opacity: 0.8
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
