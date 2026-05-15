import QtQuick 2.12

Image {
    id: root

    enum Location { Left = 0, Right = 1 }

    property int location: LaneAssistWhiteLine.Left
    property real scale: 1
    property real centerX: 512
    property real baseY: 600

    property real t: 0

    // line animation
    property real s: 0.1 + t * t * 1.9

    source: location == LaneAssistWhiteLine.Left ? "qrc:/images/lanes/white-line-left.png"
                                                 : "qrc:/images/lanes/white-line-right.png"

    x: location == LaneAssistWhiteLine.Left ? centerX - 59 : centerX + 39
    y: baseY - 100

    opacity: Math.min(1 - (1 - s) * (1 - s), 1)

    transform: [
        // line animation
        Scale {
            xScale: s
            yScale: s

            origin.x: location == LaneAssistWhiteLine.Left ? 42 : -22
            origin.y: -86
        },
        // navi scale
        Scale {
            origin.x: centerX - root.x
            origin.y: baseY - root.y

            xScale: scale
            yScale: scale
        }
    ]
}
