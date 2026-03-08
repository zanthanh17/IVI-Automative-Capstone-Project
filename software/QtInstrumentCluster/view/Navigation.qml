import QtQuick 2.12

NormalModeContentItem {
    id: navRoot

    property bool usingFallback: false

    Loader {
        id: mapLoader
        anchors.fill: parent
        source: "qrc:/view/NavigationMapLocation.qml"

        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("Navigation map load failed: " + source)
                if (!navRoot.usingFallback) {
                    navRoot.usingFallback = true
                    source = "qrc:/view/NavigationHudFallback.qml"
                }
            }
        }
    }
}
