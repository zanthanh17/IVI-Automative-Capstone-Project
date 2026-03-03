import QtQuick 2.12
import QtQuick.Effects
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

    MultiEffect {
        id: colorizedImage
        source: image
        anchors.fill: image
        colorization: 1.0
        colorizationColor: indicator.active ? indicator.activeColor : indicator.inactiveColor
        brightness: indicator.active ? 0.6 : 0.0
        contrast: indicator.active ? 0.3 : 0.0
        saturation: indicator.active ? 0.5 : 0.0
        opacity: (indicator.active ? 1.0 : 0.4) * indicator.indicatorOpacity

        Behavior on opacity { NumberAnimation {
            easing.type: Easing.InOutQuad;
            duration: TellTalesModel.opacityChangeDuration;
        }}

        Behavior on colorizationColor { ColorAnimation {
            easing.type: Easing.InOutQuad;
            duration: TellTalesModel.opacityChangeDuration;
        }}

        Behavior on brightness { NumberAnimation {
            easing.type: Easing.InOutQuad;
            duration: TellTalesModel.opacityChangeDuration;
        }}
    }

    MultiEffect {
        id: activeBoost
        source: image
        anchors.centerIn: image
        width: image.width
        height: image.height
        colorization: 1.0
        colorizationColor: indicator.activeColor
        brightness: 0.5
        blurEnabled: true
        blur: 0.3
        blurMax: 8
        opacity: indicator.active ? (1.0 * indicator.indicatorOpacity) : 0
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
