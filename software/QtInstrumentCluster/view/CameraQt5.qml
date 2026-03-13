import QtQuick 2.12
import DrowsyCamera 1.0

Item {
    id: cameraView

    property bool cameraActive: false
    readonly property bool frameReady: DrowsyCamera.frameSequence > 0 && liveFrame.status === Image.Ready
    readonly property bool hasBackendError: DrowsyCamera.errorText.length > 0
    readonly property bool showMessageOverlay: !cameraActive || !frameReady || hasBackendError

    function overlayMessage() {
        if (hasBackendError)
            return DrowsyCamera.errorText
        if (!cameraActive)
            return "Preview paused"
        if (!DrowsyCamera.running)
            return "Starting AI detector..."
        return "Waiting first processed frame..."
    }

    onCameraActiveChanged: {
        DrowsyCamera.setActive(cameraActive)
    }

    Component.onDestruction: {
        DrowsyCamera.stop()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 14
        radius: 18
        color: "#090c11"
        border.width: 1
        border.color: "#273141"
        clip: true

        Image {
            id: liveFrame
            anchors.fill: parent
            source: cameraView.cameraActive
                    ? ("image://drowsy/live?seq=" + DrowsyCamera.frameSequence)
                    : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 44
            color: "#99000000"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "Driver Camera"
                color: "#eff4ff"
                font.pixelSize: 16
                font.bold: true
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: DrowsyCamera.statusText
                color: "#d7e2f5"
                font.pixelSize: 12
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: fpsText.implicitWidth + 18
            height: 28
            radius: 14
            color: "#a0000000"
            visible: cameraView.cameraActive

            Text {
                id: fpsText
                anchors.centerIn: parent
                text: "AI FPS: " + DrowsyCamera.detectorFps.toFixed(1)
                color: "#e9f2ff"
                font.pixelSize: 12
                font.bold: true
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#8c000000"
            visible: cameraView.showMessageOverlay

            Text {
                anchors.centerIn: parent
                width: parent.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#edf2ff"
                font.pixelSize: 20
                text: cameraView.overlayMessage()
            }
        }
    }
}
