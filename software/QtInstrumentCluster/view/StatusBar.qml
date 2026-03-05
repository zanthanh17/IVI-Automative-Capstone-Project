import QtQuick 2.12
import Units 1.0
import MainModel 1.0
import Style 1.0

Item {
    id: root

    property date currentDateTime: new Date()

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.currentDateTime = new Date()
    }

    Column {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 20
        anchors.rightMargin: 42
        spacing: 0

        Text {
            text: Qt.formatDateTime(root.currentDateTime, "hh:mm")
            horizontalAlignment: Text.AlignRight
            color: Style.lightPeriwinkle
            font.pixelSize: 24
            font.bold: true
            font.family: "Sarabun"
        }

        Text {
            text: Qt.formatDateTime(root.currentDateTime, "ddd, dd MMM yyyy")
            horizontalAlignment: Text.AlignRight
            color: "#657080"
            font.pixelSize: 11
            font.family: "Sarabun"
        }
    }

    Text {
        id: odo
        anchors.bottom: parent.bottom;
        anchors.bottomMargin: 42;
        anchors.left: parent.left;
        anchors.leftMargin: 49;
        text: "ODO";
        color: "#657080"
        font.pixelSize: 12;
        font.family: "Sarabun";
    }

    Text {
        id: odoValue
        anchors.baseline: odo.baseline;
        anchors.left: odo.right;
        anchors.leftMargin: 4;
        text: Units.toInt(Units.kilometersToLongDistanceUnit(MainModel.odo));
        color: Style.lightPeriwinkle;
        font.pixelSize: 20;
        font.family: "Sarabun";
    }

    Text {
        id: odoUnit
        anchors.baseline: odo.baseline;
        anchors.left: odoValue.right;
        anchors.leftMargin: 4;
        text: Units.longDistanceUnit;
        color: "#657080"
        font.pixelSize: 12;
        font.family: "Sarabun";
    }

    Text {
        id: range
        anchors.bottom: parent.bottom;
        anchors.bottomMargin: 42;
        x: 279
        text: "RANGE";
        color: "#657080"
        font.pixelSize: 12;
        font.family: "Sarabun";
    }

    Text {
        id: rangeValue
        anchors.baseline: range.baseline;
        anchors.left: range.right;
        anchors.leftMargin: 4;
        text: Units.toInt(Units.kilometersToLongDistanceUnit(MainModel.range));
        color: Style.lightPeriwinkle;
        font.pixelSize: 20;
        font.family: "Sarabun";
    }

    Text {
        id: rangeUnit
        anchors.baseline: range.baseline;
        anchors.left: rangeValue.right;
        anchors.leftMargin: 4;
        text: Units.longDistanceUnit;
        color: "#657080"
        font.pixelSize: 12;
        font.family: "Sarabun";
    }

    LinearGauge {
        anchors.bottom: parent.bottom;
        anchors.bottomMargin: 42;
        x: 730;
        image: "qrc:/images/status/fuel.png";
        emptyText: "R";
        value: MainModel.fuelLevel;
    }

    LinearGauge {
        anchors.bottom: parent.bottom;
        anchors.bottomMargin: 42;
        x: 870;
        image: "qrc:/images/status/battery.png";
        emptyText: "E";
        value: MainModel.batteryLevel;
    }
}
