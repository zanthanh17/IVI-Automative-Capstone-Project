import QtQuick 2.12
import Style 1.0
import TellTalesModel 1.0

Item {
    id: indicator
    height: 28
    width: image.width + 15

    property alias source: image.source
    property bool active: false
    property color activeColor: Style.highlighterGreen
    property color inactiveColor: Style.iconInactiveBlue
    property real indicatorOpacity: 1.0
    property alias blinking: indicatorBlinkAnimation.running

    function boostedColor(c) {
        return Qt.lighter(c, 1.35)
    }

    Image {
        id: image
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        visible: false
        onStatusChanged: colorizedImage.requestPaint()
    }

    Canvas {
        id: colorizedImage
        anchors.fill: image
        smooth: true
        antialiasing: true

        property color iconColor: indicator.active ? indicator.boostedColor(indicator.activeColor) : indicator.inactiveColor
        property real iconOpacity: (indicator.active ? Style.iconActiveOpacity : Style.iconInactiveOpacity) * indicator.indicatorOpacity
        property color glowColor: indicator.active ? indicator.boostedColor(indicator.activeColor) : indicator.inactiveColor
        property real glowOpacity: indicator.active ? Style.iconActiveShadowOpacity : Style.iconInactiveShadowOpacity
        property real glowBlur: indicator.active ? 8 : 4

        onIconColorChanged: requestPaint()
        onIconOpacityChanged: requestPaint()
        onGlowColorChanged: requestPaint()
        onGlowOpacityChanged: requestPaint()
        onGlowBlurChanged: requestPaint()

        Behavior on iconOpacity {
            NumberAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
        }

        Behavior on iconColor {
            ColorAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
        }

        Behavior on glowOpacity {
            NumberAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            if (image.status !== Image.Ready) {
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
            ctx.drawImage(image, 0, 0, w, h)
            ctx.restore()

            ctx.save()
            ctx.globalAlpha = iconOpacity
            ctx.drawImage(image, 0, 0, w, h)
            ctx.globalCompositeOperation = "source-atop"
            ctx.fillStyle = iconColor
            ctx.fillRect(0, 0, w, h)
            ctx.restore()
        }
    }

    SequentialAnimation {
        id: indicatorBlinkAnimation
        loops: Animation.Infinite
        alwaysRunToEnd: true

        ScriptAction { script: indicator.active = true }
        PauseAnimation { duration: 400 }
        ScriptAction { script: indicator.active = false }
        PauseAnimation { duration: 300 }
    }
}
