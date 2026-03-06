import QtQuick 2.12
import Style 1.0
import NormalModeModel 1.0

Row {
    signal clicked(int index)
    property int currentIndex
    id: menu
    spacing: 6

    Repeater {
        model: ListModel {
            ListElement { text: "Play"; image: "qrc:/images/menu/music.png" }
            ListElement { text: "Navi"; image: "qrc:/images/menu/navi.png" }
            ListElement { text: "Weather"; image: "qrc:/images/menu/weather.png" }
            ListElement { text: "Bluetooth"; image: "qrc:/images/menu/bluetooth.png" }
            ListElement { text: "Setup"; image: "qrc:/images/menu/setup.png" }
        }

        delegate: Item {
            width: 64
            height: 42
            property bool active: index == currentIndex

            Image {
                id: menuIconSource
                source: model.image
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 2
                visible: false
                onStatusChanged: menuIcon.requestPaint()
            }

            Canvas {
                id: menuIcon
                anchors.fill: menuIconSource
                smooth: true
                antialiasing: true

                property color iconColor: parent.active ? Style.iconActiveBlue : Style.iconInactiveBlue
                property real iconOpacity: parent.active ? Style.iconActiveOpacity : Style.iconInactiveOpacity
                property color glowColor: parent.active ? Style.iconActiveBlue : Style.iconInactiveBlue
                property real glowOpacity: parent.active ? Style.iconActiveShadowOpacity : Style.iconInactiveShadowOpacity
                property real glowBlur: parent.active ? 8 : 4

                onIconColorChanged: requestPaint()
                onIconOpacityChanged: requestPaint()
                onGlowColorChanged: requestPaint()
                onGlowOpacityChanged: requestPaint()
                onGlowBlurChanged: requestPaint()

                Behavior on iconOpacity { NumberAnimation { duration: 200 } }
                Behavior on iconColor { ColorAnimation { duration: 200 } }
                Behavior on glowOpacity { NumberAnimation { duration: 200 } }

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()

                    if (menuIconSource.status !== Image.Ready) {
                        return
                    }

                    var w = width
                    var h = height

                    ctx.save()
                    ctx.globalAlpha = glowOpacity
                    ctx.shadowColor = glowColor
                    ctx.shadowBlur = glowBlur
                    ctx.shadowOffsetX = 0
                    ctx.shadowOffsetY = 0
                    ctx.drawImage(menuIconSource, 0, 0, w, h)
                    ctx.restore()

                    ctx.save()
                    ctx.globalAlpha = iconOpacity
                    ctx.drawImage(menuIconSource, 0, 0, w, h)
                    ctx.globalCompositeOperation = "source-atop"
                    ctx.fillStyle = iconColor
                    ctx.fillRect(0, 0, w, h)
                    ctx.restore()
                }
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
                onClicked: menu.clicked(index)
            }
        }
    }
}
