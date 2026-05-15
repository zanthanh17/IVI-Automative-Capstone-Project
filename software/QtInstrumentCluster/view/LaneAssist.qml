import QtQuick 2.12
import MainModel 1.0

Item {
    id: laneAssist

    property real redBorderOpacity: 0
    property real scale: 1
    property real centerX: width / 2
    property real baseY: height

    Image {
        id: leftLaneAssist

        source: "qrc:/images/lanes/red-border-left.png"
        opacity: redBorderOpacity
        x: laneAssist.centerX - 80
        y: laneAssist.baseY - 220
        width: 70
        height: 200

        transform: Scale {
            origin.x: laneAssist.centerX - leftLaneAssist.x
            origin.y: laneAssist.baseY - leftLaneAssist.y

            xScale: laneAssist.scale
            yScale: laneAssist.scale
        }
    }

    Image {
        id: rightLaneAssist

        source: "qrc:/images/lanes/red-border-right.png"
        opacity: redBorderOpacity
        x: laneAssist.centerX + 10
        y: laneAssist.baseY - 220
        width: 70
        height: 200

        transform: Scale {
            origin.x: laneAssist.centerX - rightLaneAssist.x
            origin.y: laneAssist.baseY - rightLaneAssist.y

            xScale: laneAssist.scale
            yScale: laneAssist.scale
        }
    }

    SequentialAnimation {
        id: laneAssistAnimation
        loops: 4
        alwaysRunToEnd: true

        NumberAnimation {
            target: laneAssist
            property: "redBorderOpacity"
            from: 0
            to: 0.7
            easing.type: Easing.OutQuad
            duration: 600
        }

        NumberAnimation {
            target: laneAssist
            property: "redBorderOpacity"
            from: 0.7
            to: 0
            easing.type: Easing.InQuad
            duration: 600
        }

        PauseAnimation {
            duration: 300
        }
    }

    LaneAssistWhiteLine {
        t: t0
        scale: laneAssist.scale
        centerX: laneAssist.centerX
        baseY: laneAssist.baseY
        location: LaneAssistWhiteLine.Left
    }

    LaneAssistWhiteLine {
        t: t1 > 1 ? t1 - 1 : t1
        scale: laneAssist.scale
        centerX: laneAssist.centerX
        baseY: laneAssist.baseY
        location: LaneAssistWhiteLine.Left
    }

    LaneAssistWhiteLine {
        t: t0
        scale: laneAssist.scale
        centerX: laneAssist.centerX
        baseY: laneAssist.baseY
        location: LaneAssistWhiteLine.Right
    }

    LaneAssistWhiteLine {
        t: t1 > 1 ? t1 - 1 : t1
        scale: laneAssist.scale
        centerX: laneAssist.centerX
        baseY: laneAssist.baseY
        location: LaneAssistWhiteLine.Right
    }

    property real t0: 0
    property real t1: t0 + 0.5

    Timer {
        id: laneTimer
        interval: 16  // ~60 FPS
        repeat: true
        running: MainModel.laneAssistCarMoving && MainModel.speed > 0

        onTriggered: {
            // speed km/h → tốc độ animation tỷ lệ thuận
            // speed=60 → 1 cycle/giây, speed=120 → 2 cycle/giây
            var step = (MainModel.speed / 60.0) * (interval / 1000.0)
            laneAssist.t0 = (laneAssist.t0 + step) % 1.0
        }
    }

    onVisibleChanged: {
        if (!visible) t0 = 0
    }
}
