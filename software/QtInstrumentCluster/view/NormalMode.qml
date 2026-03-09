import QtQuick 2.12
import NormalModeModel 1.0
import Style 1.0
import MainModel 1.0
import Units 1.0
Item {
    id: root
    property real scale: 1.0
    property int menu: NormalModeModel.menu;
    readonly property real layoutMargin: 24
    readonly property real layoutGap: 20
    readonly property real topPaneHeight: 64
    readonly property real topPaneY: layoutMargin
    readonly property real topCardWidth: Math.min(root.width - layoutMargin * 2, 520)
    
    readonly property real leftPaneX: layoutMargin
    readonly property real leftPaneY: topPaneY + topPaneHeight + layoutGap
    readonly property real leftPaneWidth: 500
    readonly property real leftPaneHeight: root.height - leftPaneY - layoutMargin
    
    readonly property real rightPaneX: leftPaneX + leftPaneWidth + layoutGap
    readonly property real rightPaneY: topPaneY + topPaneHeight + layoutGap
    readonly property real rightPaneWidth: root.width - rightPaneX - layoutMargin
    
    readonly property real menuPaneHeight: 70
    readonly property real rightPaneHeight: root.height - rightPaneY - layoutMargin - menuPaneHeight - layoutGap
    
    readonly property real bottomPaneY: root.height - layoutMargin - menuPaneHeight
    
    readonly property real contentTopY: topLine.y + topLine.height + 2
    readonly property real rightContentHeight: rightPaneHeight - (contentTopY - rightPaneY) - layoutGap
    readonly property real gaugeTopY: leftPaneY + 32
    readonly property real gaugeInset: 8
    readonly property real vehicleBottomInset: 135
    readonly property real vehiclePanelCenterX: leftPaneX + leftPaneWidth / 2
    // Gauge frame in BaseGauge is asymmetric (half-arc), so visible center is not width/2.
    readonly property real gaugeFrameVisualCenterX: 83.07
    readonly property real gaugeFrameWidth: 360
    readonly property real gaugeFrameCenterX: gaugeFrameWidth / 2
    readonly property real gaugeFrameXInItem: (leftGauge.width - gaugeFrameWidth) / 2
    readonly property real leftGaugeVisualCenterX: leftGauge.x + (60 - gaugeFrameXInItem)
                                                   + ((gaugeFrameXInItem + gaugeFrameVisualCenterX) - (60 - gaugeFrameXInItem)) * leftGauge.scale
    readonly property real rightGaugeMirroredCenterX: gaugeFrameCenterX
                                                      + ((gaugeFrameXInItem + gaugeFrameVisualCenterX) - gaugeFrameCenterX) * (-1)
    readonly property real rightGaugeVisualCenterX: rightGauge.x + (280 - gaugeFrameXInItem)
                                                    + (rightGaugeMirroredCenterX - (280 - gaugeFrameXInItem)) * rightGauge.scale
    readonly property real gaugesMidX: (leftGaugeVisualCenterX + rightGaugeVisualCenterX) / 2
    readonly property real vehicleCenterOffsetX: gaugesMidX - vehiclePanelCenterX

    // Card Backgrounds
    Rectangle {
        id: topCardBg
        x: (root.width - width) / 2
        y: topPaneY
        width: topCardWidth
        height: topPaneHeight
        color: Style.backgroundPanel
        radius: 26
        opacity: 0.96
        z: -1
    }

    Rectangle {
        id: leftCardBg
        x: leftPaneX
        y: leftPaneY
        width: leftPaneWidth
        height: leftPaneHeight
        color: Style.backgroundPanel
        radius: 26
        opacity: 0.96
        z: -1
    }

    Rectangle {
        id: rightCardBg
        x: rightPaneX
        y: rightPaneY
        width: rightPaneWidth
        height: rightPaneHeight
        color: Style.backgroundPanel
        radius: 26
        opacity: 0.96
        z: -1
    }

    Rectangle {
        id: bottomCardBg
        x: rightPaneX
        y: bottomPaneY
        width: rightPaneWidth
        height: menuPaneHeight
        color: Style.backgroundPanel
        radius: 26
        opacity: 0.96
        z: -1
    }

    LaneAssist {
        anchors.fill: parent
        scale: root.scale * 1.35
        centerX: vehiclePanelCenterX + vehicleCenterOffsetX
        baseY: leftPaneY + leftPaneHeight - vehicleBottomInset
        z: 1
    }

    // Right Card contents fill the entire area
    Item {
        id: mainElement;
        x: rightPaneX
        y: rightPaneY
        width: rightPaneWidth
        height: rightPaneHeight
        clip: true

        MediaPlayer {
            activeMode: active;
            selected: menu == NormalModeModel.MediaPlayerMenu;
            anchors.fill: parent;
        }

        Navigation {
            activeMode: active;
            selected: menu == NormalModeModel.NavigationMenu;
            anchors.fill: parent;
        }

        Weather {
            activeMode: active;
            selected: menu == NormalModeModel.WeatherMenu;
            anchors.fill: parent;
        }

        Bluetooth {
            activeMode: active;
            selected: menu == NormalModeModel.BluetoothMenu;
            anchors.fill: parent;
        }

        Setup {
            activeMode: active;
            // Tạm dùng CarStatusMenu làm trang Setup
            selected: menu == NormalModeModel.CarStatusMenu;
            anchors.fill: parent;
        }
    }

    Gauge {
        id: leftGauge;
        x: leftPaneX + gaugeInset
        y: gaugeTopY
        scale: 0.90
        valueHorizontalCenterOffset: -96
        labelHorizontalCenterOffset: -96
        leftOrientation: true;
        value: Units.kilometersToLongDistanceUnit(MainModel.speed)
        maxValue: Units.maximumSpeed
        valueText: ""
        textLabel: ""

        Text {
            id: speedUnitOnly
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -78
            anchors.verticalCenterOffset: -2
            text: "KM/H"
            color: Style.lightPeriwinkle
            font.pixelSize: 18
            font.bold: false

            transform: Scale {
                origin.x: leftGauge.transformOriginX - speedUnitOnly.x
                origin.y: 340 - speedUnitOnly.y
                xScale: leftGauge.scale
                yScale: leftGauge.scale
            }
        }
    }

    Gauge {
        id: rightGauge;
        x: leftPaneX + leftPaneWidth - rightGauge.width - gaugeInset
        y: gaugeTopY
        scale: 0.90
        valueHorizontalCenterOffset: 96
        labelHorizontalCenterOffset: 96
        leftOrientation: false;
        value: MainModel.rpm / 1000;
        valueText: ""
        maxValue: MainModel.maxRpm / 1000;
        maxAngle: 180
        textLabel: ""

        Text {
            id: rpmUnitOnly
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 78
            anchors.verticalCenterOffset: -2

            horizontalAlignment: Text.AlignHCenter
            text: "x1000 RPM"
            color: Style.lightPeriwinkle;
            font.pixelSize: 18
            font.bold: false

            transform: Scale {
                origin.x: rightGauge.transformOriginX - rpmUnitOnly.x
                origin.y: 340 - rpmUnitOnly.y
                xScale: rightGauge.scale
                yScale: rightGauge.scale
            }
        }
    }

    Menu {
        id: normalMenu;
        opacity: topLine.opacity;
        anchors.horizontalCenter: undefined
        x: rightPaneX + (rightPaneWidth - width) / 2
        y: bottomPaneY + (menuPaneHeight - height) / 2
        currentIndex: menu;
        onClicked: NormalModeModel.menu = index;
    }
}
