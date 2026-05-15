import QtQuick 2.12

NormalModeContentItem {
    id: navRoot

    property string mapboxSource: "qrc:/view/NavigationMapLocation.qml"
    property bool mapLoadFailed: false

    Loader {
        id: mapLoader
        anchors.fill: parent
        source: navRoot.mapboxSource

        onStatusChanged: {
            navRoot.mapLoadFailed = (status === Loader.Error)
            if (status === Loader.Error) {
                console.error("Mapbox navigation view load failed:", source)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: navRoot.mapLoadFailed
        color: "#060d15"

        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#d8e8f8"
            font.pixelSize: 16
            text: "Mapbox map failed to initialize. Check Qt mapboxgl plugin and MAPBOX_ACCESS_TOKEN."
        }
    }
}
