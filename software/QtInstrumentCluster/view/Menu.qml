import QtQuick 2.12
import QtGraphicalEffects 1.12
import Style 1.0
import NormalModeModel 1.0

Row {
    signal clicked(int index);
    property int currentIndex;
    id: menu;
    Repeater {
        model: ListModel {
            ListElement { text: "Play"; image: "qrc:/images/menu/play.png"}
            ListElement { text: "Navi"; image: "qrc:/images/menu/navi.png"}
            ListElement { text: "Phone"; image: "qrc:/images/menu/phone.png"}
            ListElement { text: "Setup"; image: "qrc:/images/menu/setup.png"}
        }
        delegate: Item {
            width: 52;
            height: 42;
            property bool active: index == currentIndex;

            Image {
                id: menuIcon
                source: model.image;
                anchors.horizontalCenter: parent.horizontalCenter;
                anchors.top: parent.top
                anchors.topMargin: 2
                visible: false
            }

            /* Colorize: bright blue when active, dim when inactive */
            ColorOverlay {
                id: colorizedIcon
                source: menuIcon
                anchors.fill: menuIcon
                color: parent.active ? Style.brightBlue : "#3a5070"
                opacity: parent.active ? 1.0 : 0.5

                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            /* Glow effect when selected */
            Glow {
                visible: parent.active
                anchors.fill: colorizedIcon
                source: colorizedIcon
                color: Style.brightBlue
                radius: 6
                samples: 13
                opacity: parent.active ? 0.5 : 0
                Behavior on opacity { NumberAnimation { duration: 250 } }
            }

            Text {
                text: model.text;
                anchors.bottom: parent.bottom;
                anchors.horizontalCenter: parent.horizontalCenter;
                opacity: parent.active ? 1 : 0;
                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InCubic } }
                font.pixelSize: 11;
                font.family: "Sarabun";
                color: parent.active ? Style.brightBlue : Style.lightPeriwinkle;
            }
        }
    }
}
