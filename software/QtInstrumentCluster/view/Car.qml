import QtQuick 2.12

Item {
    id: carRoot
    property real bottomInset: 0
    property real centerOffsetX: 0
    property real carScale: 1.0

    Image {
        id: bg
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            horizontalCenterOffset: carRoot.centerOffsetX
            bottomMargin: carRoot.bottomInset
        }
        source: "qrc:/images/Model_3-2_new.png"
        sourceSize.width: 160
        sourceSize.height: 160
        fillMode: Image.PreserveAspectFit

        onStatusChanged: {
            if (status === Image.Ready) {
                console.log("[Car.qml] Loaded car image:", source, "size:", implicitWidth, "x", implicitHeight)
            }
            if (status === Image.Error) {
                console.warn("[Car.qml] Failed to load car image:", source)
            }
        }

        transform: Scale {
            origin.x: bg.implicitWidth / 2
            origin.y: bg.implicitHeight
            xScale: carRoot.carScale
            yScale: carRoot.carScale
        }
        z: 2
    }

    Image {
        id: highlights
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            horizontalCenterOffset: carRoot.centerOffsetX
            bottomMargin: carRoot.bottomInset
        }
        source: "qrc:/images/car-highlights.png"
        visible: false // User is replacing the whole car look, hide the old highlights

        transform: Scale {
            origin.x: highlights.implicitWidth / 2
            origin.y: highlights.implicitHeight
            xScale: carRoot.carScale
            yScale: carRoot.carScale
        }
    }
}
