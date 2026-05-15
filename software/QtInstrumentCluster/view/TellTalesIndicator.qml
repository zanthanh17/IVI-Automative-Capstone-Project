import QtQuick 2.12
import QtGraphicalEffects 1.12
import Style 1.0
import TellTalesModel 1.0

Item {
    id: indicator
    height: 28
    width: 28 + 15

    property alias source: image.source
    property bool active: false
    property color activeColor: Style.highlighterGreen
    property color inactiveColor: "#5579b8"
    property real indicatorOpacity: 1.0
    property alias blinking: indicatorBlinkAnimation.running

    Image {
        id: image
        width: 28
        height: 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 28
        sourceSize.height: 28
        visible: false
        layer.enabled: true
    }

    ColorOverlay {
        id: colorizedImage
        width: image.width
        height: image.height
        anchors.horizontalCenter: image.horizontalCenter
        anchors.verticalCenter: image.verticalCenter
        source: image
        color: indicator.active ? indicator.activeColor : indicator.inactiveColor
        opacity: (indicator.active ? Style.iconActiveOpacity : Style.iconInactiveOpacity) * indicator.indicatorOpacity
        visible: true

        Behavior on opacity {
            NumberAnimation {
                easing.type: Easing.InOutQuad
                duration: TellTalesModel.opacityChangeDuration
            }
        }

        Behavior on color {
            ColorAnimation {
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
