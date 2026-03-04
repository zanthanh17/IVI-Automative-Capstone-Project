import QtQuick 2.12
import QtQuick.Effects
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
    }

    MultiEffect {
        id: colorizedImage
        anchors.fill: image
        source: image
        colorization: 1.0
        colorizationColor: indicator.active ? indicator.boostedColor(indicator.activeColor) : indicator.inactiveColor
        brightness: indicator.active ? Style.iconActiveBrightness : Style.iconInactiveBrightness
        saturation: indicator.active ? Style.iconActiveSaturation : Style.iconInactiveSaturation
        contrast: indicator.active ? Style.iconActiveContrast : Style.iconInactiveContrast
        opacity: (indicator.active ? Style.iconActiveOpacity : Style.iconInactiveOpacity) * indicator.indicatorOpacity
        shadowEnabled: true
        shadowColor: indicator.active ? indicator.boostedColor(indicator.activeColor) : indicator.inactiveColor
        shadowOpacity: indicator.active ? Style.iconActiveShadowOpacity : Style.iconInactiveShadowOpacity
        shadowBlur: Style.iconShadowBlur
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
        shadowScale: indicator.active ? Style.iconActiveShadowScale : Style.iconInactiveShadowScale

        Behavior on opacity {
            NumberAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
        }

        Behavior on colorizationColor {
            ColorAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
        }

        Behavior on brightness {
            NumberAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
        }

        Behavior on shadowOpacity {
            NumberAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
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
