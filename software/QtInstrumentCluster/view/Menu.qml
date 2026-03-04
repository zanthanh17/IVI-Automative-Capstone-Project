import QtQuick 2.12
import QtQuick.Effects
import Style 1.0
import NormalModeModel 1.0

Row {
    signal clicked(int index)
    property int currentIndex
    id: menu

    Repeater {
        model: ListModel {
            ListElement { text: "Play"; image: "qrc:/images/menu/play.png" }
            ListElement { text: "Navi"; image: "qrc:/images/menu/navi.png" }
            ListElement { text: "Phone"; image: "qrc:/images/menu/phone.png" }
            ListElement { text: "Setup"; image: "qrc:/images/menu/setup.png" }
        }

        delegate: Item {
            width: 52
            height: 42
            property bool active: index == currentIndex

            Image {
                id: menuIconSource
                source: model.image
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 2
                visible: false
            }

            MultiEffect {
                id: menuIcon
                anchors.fill: menuIconSource
                source: menuIconSource
                colorization: 1.0
                colorizationColor: parent.active ? Style.iconActiveBlue : Style.iconInactiveBlue
                brightness: parent.active ? Style.iconActiveBrightness : Style.iconInactiveBrightness
                saturation: parent.active ? Style.iconActiveSaturation : Style.iconInactiveSaturation
                contrast: parent.active ? Style.iconActiveContrast : Style.iconInactiveContrast
                opacity: parent.active ? Style.iconActiveOpacity : Style.iconInactiveOpacity
                shadowEnabled: true
                shadowColor: parent.active ? Style.iconActiveBlue : Style.iconInactiveBlue
                shadowOpacity: parent.active ? Style.iconActiveShadowOpacity : Style.iconInactiveShadowOpacity
                shadowBlur: Style.iconShadowBlur
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                shadowScale: parent.active ? Style.iconActiveShadowScale : Style.iconInactiveShadowScale

                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on colorizationColor { ColorAnimation { duration: 200 } }
                Behavior on brightness { NumberAnimation { duration: 200 } }
                Behavior on shadowOpacity { NumberAnimation { duration: 200 } }
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
                font.family: "Sarabun"
                color: parent.active ? Style.brightBlue : Style.lightPeriwinkle
            }
        }
    }
}
