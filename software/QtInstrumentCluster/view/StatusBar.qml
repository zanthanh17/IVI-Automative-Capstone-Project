import QtQuick 2.12
import Units 1.0
import MainModel 1.0
import Style 1.0

Item {
    id: root

    Text {
        id: odo
        anchors.top: parent.top
        anchors.topMargin: 32
        anchors.left: parent.left;
        anchors.leftMargin: 38
        text: "ODO";
        color: "#657080"
        font.pixelSize: 12;
    }

    Text {
        id: odoValue
        anchors.baseline: odo.baseline;
        anchors.left: odo.right;
        anchors.leftMargin: 4;
        text: Units.toInt(Units.kilometersToLongDistanceUnit(Math.max(MainModel.odo, 0)));
        color: Style.lightPeriwinkle;
        font.pixelSize: 20;
    }

    Text {
        id: odoUnit
        anchors.baseline: odo.baseline;
        anchors.left: odoValue.right;
        anchors.leftMargin: 4;
        text: Units.longDistanceUnit;
        color: "#657080"
        font.pixelSize: 12;
    }

    Text {
        id: range
        anchors.top: parent.top
        anchors.topMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 116
        text: "RANGE";
        color: "#657080"
        font.pixelSize: 12;
    }

    Text {
        id: rangeValue
        anchors.baseline: range.baseline;
        anchors.left: range.right;
        anchors.leftMargin: 4;
        text: Units.toInt(Units.kilometersToLongDistanceUnit(Math.max(MainModel.range, 0)));
        color: Style.lightPeriwinkle;
        font.pixelSize: 20;
    }

    Text {
        id: rangeUnit
        anchors.baseline: range.baseline;
        anchors.left: rangeValue.right;
        anchors.leftMargin: 4;
        text: Units.longDistanceUnit;
        color: "#657080"
        font.pixelSize: 12;
    }

    LinearGauge {
        id: fuelGauge
        anchors.bottom: parent.bottom;
        anchors.bottomMargin: 46
        anchors.left: parent.left
        anchors.leftMargin: 18
        image: "qrc:/images/status/fuel.png";
        emptyText: "R";
        value: MainModel.fuelLevel;
    }

    LinearGauge {
        id: batteryGauge
        anchors.bottom: parent.bottom;
        anchors.bottomMargin: 46
        anchors.right: parent.right
        anchors.rightMargin: 18
        image: "qrc:/images/status/battery.png";
        emptyText: "E";
        value: MainModel.batteryLevel;
    }
}
