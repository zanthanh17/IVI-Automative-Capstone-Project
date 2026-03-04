import QtQuick 2.12
import QtGraphicalEffects 1.12
import Style 1.0
import TellTalesModel 1.0

Item {
    id: indicator
    height: 28;
    width: image.width + 15;

    property alias source: image.source;
    property bool active: false;
    property color activeColor: Style.highlighterGreen
    property color inactiveColor: Style.darkBlue;
    property real indicatorOpacity: 1.0;
    property alias blinking: indicatorBlinkAnimation.running

    Image {
        id: image;
        anchors.horizontalCenter: parent.horizontalCenter;
        anchors.verticalCenter: parent.verticalCenter;
        visible: false
    }

    ColorOverlay {
        id: colorizedImage
        source: image
        anchors.fill: image
        color: indicator.active ? indicator.activeColor : indicator.inactiveColor
        opacity: (indicator.active ? 0.75 : 0.3) * indicator.indicatorOpacity

        Behavior on opacity { NumberAnimation {
            easing.type: Easing.InOutQuad;
            duration: TellTalesModel.opacityChangeDuration;
        }}

        Behavior on color { ColorAnimation {
            easing.type: Easing.InOutQuad;
            duration: TellTalesModel.opacityChangeDuration;
        }}
    }

    Glow {
        id: activeBoost
        anchors.fill: colorizedImage
        source: colorizedImage
        color: indicator.activeColor
        radius: 3
        samples: 7
        opacity: indicator.active ? (0.35 * indicator.indicatorOpacity) : 0
        scale: 1.15

        Behavior on opacity { NumberAnimation {
            easing.type: Easing.InOutQuad;
            duration: TellTalesModel.opacityChangeDuration;
        }}
    }

    SequentialAnimation {
        id: indicatorBlinkAnimation
        loops: Animation.Infinite
        alwaysRunToEnd: true

        ScriptAction {
            script: indicator.active = true;
        }

        PauseAnimation {
            duration: 400
        }

        ScriptAction {
            script: indicator.active = false;
        }

        PauseAnimation {
            duration: 300
        }
    }
}
