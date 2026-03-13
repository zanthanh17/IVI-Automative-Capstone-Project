import QtQuick 2.12

NormalModeContentItem {
    id: cameraRoot

    readonly property string implementationSource: "qrc:/view/CameraQt5.qml"
    readonly property bool shouldRunCamera: selected && visible && activeMode

    function syncCameraState() {
        if (cameraLoader.status !== Loader.Ready || !cameraLoader.item)
            return
        if (cameraLoader.item.cameraActive !== undefined)
            cameraLoader.item.cameraActive = shouldRunCamera
    }

    onSelectedChanged: syncCameraState()
    onVisibleChanged: syncCameraState()
    onActiveModeChanged: syncCameraState()

    Loader {
        id: cameraLoader
        anchors.fill: parent
        active: cameraRoot.selected || cameraRoot.visible
        source: cameraRoot.implementationSource

        onLoaded: cameraRoot.syncCameraState()
    }

    Rectangle {
        anchors.fill: parent
        color: "#0f1319"
        visible: cameraLoader.status === Loader.Error

        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#d9e3f0"
            font.pixelSize: 18
            text: "Cannot load camera page. Check DrowsyCamera module and runtime deps."
        }
    }
}
