import QtQuick 2.12

NormalModeContentItem {
    id: navRoot

    property int loadStage: 0
    property var stageSources: [
        "qrc:/view/NavigationMapLocation.qml",
        "qrc:/view/NavigationMapWebEngine.qml",
        "qrc:/view/NavigationHudFallback.qml"
    ]

    Loader {
        id: mapLoader
        anchors.fill: parent
        source: navRoot.stageSources[navRoot.loadStage]

        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("Navigation view load failed:", source)
                if (navRoot.loadStage < navRoot.stageSources.length - 1) {
                    navRoot.loadStage += 1
                    source = navRoot.stageSources[navRoot.loadStage]
                }
            }
        }
    }
}
