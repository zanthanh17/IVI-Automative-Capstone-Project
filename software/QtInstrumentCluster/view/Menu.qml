import QtQuick 2.12
import QtGraphicalEffects 1.12
import Style 1.0

Row {
    signal clicked(int menuIndex, string action)
    property int currentIndex
    id: menu
    spacing: 6

    Repeater {
        model: ListModel {
            ListElement { text: "Play"; image: "qrc:/images/menu/music.png"; menuIndex: 0; action: "" }
            ListElement { text: "Navi"; image: "qrc:/images/menu/navi.png"; menuIndex: 1; action: "" }
            ListElement { text: "Weather"; image: "qrc:/images/menu/weather.png"; menuIndex: 2; action: "" }
            ListElement { text: "Setup"; image: "qrc:/images/menu/setup.png"; menuIndex: 3; action: "" }
        }

        delegate: Item {
            width: 64
            height: 42
            property bool active: model.action === "" && model.menuIndex === currentIndex

            Image {
                id: menuIconSource
                source: model.image
                width: 24
                height: 24
                sourceSize.width: 24
                sourceSize.height: 24
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 2
                visible: false
                layer.enabled: true
            }

            ColorOverlay {
                id: menuIcon
                width: menuIconSource.width
                height: menuIconSource.height
                anchors.horizontalCenter: menuIconSource.horizontalCenter
                anchors.top: menuIconSource.top
                source: menuIconSource
                color: parent.active ? Style.iconActiveBlue : Style.iconInactiveBlue
                opacity: parent.active ? Style.iconActiveOpacity : Style.iconInactiveOpacity
                visible: true

                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: 18
                height: 2
                radius: 1
                color: Style.brightBlue
                opacity: parent.active ? 1.0 : 0.0

                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Text {
                text: model.text
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: parent.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InCubic } }
                font.pixelSize: 11
                color: parent.active ? Style.brightBlue : Style.lightPeriwinkle
            }

            MouseArea {
                anchors.fill: parent
                onClicked: menu.clicked(model.menuIndex, model.action)
            }
        }
    }
}
