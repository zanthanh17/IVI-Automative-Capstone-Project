import QtQuick 2.12
import LiveCamera 1.0
import Style 1.0

Item {
    id: root

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        LiveCameraItem {
            id: cameraItem
            anchors.fill: parent
        }

        Text {
            text: cameraItem.running ? "AI Model Warming up (Wait 5-10s)..." : "Connecting to Camera Daemon..."
            color: "white"
            anchors.centerIn: parent
            font.pixelSize: 20
            visible: !cameraItem.hasFrames
        }

        // Tap to dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.visible = false
        }
        
        Text {
            text: "TAP ANYWHERE TO CLOSE"
            color: "white"
            font.pixelSize: 14
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            opacity: 0.6
        }
    }
}
