import QtQuick 2.12
import Style 1.0
import Weather 1.0
import NavigationFeed 1.0

NormalModeContentItem {
    id: weatherRoot

    property string cityName: Weather.cityName
    property string detailText: Weather.detailText
    property int currentTemp: Weather.temperature
    property string conditionText: Weather.conditionText
    property string iconType: Weather.iconType
    property string lastUpdated: Weather.lastUpdated
    property bool loading: Weather.loading
    property string weatherError: Weather.errorString
    readonly property color accentColor: accentColorForType(iconType)
    readonly property bool offline: weatherError.length > 0
    readonly property bool waitingForGps: !NavigationFeed.hasPositionFix
                                          && !offline
                                          && !loading
                                          && lastUpdated.length === 0
    readonly property string resolvedCityName: cityName.length > 0 ? cityName : "Vehicle location"
    readonly property string resolvedCondition: waitingForGps
                                               ? "Waiting for GPS"
                                               : loading
                                               ? "Refreshing weather"
                                               : (conditionText.length > 0 ? conditionText : "--")

    function iconSourceForType(type) {
        if (type === "sun") {
            return "qrc:/images/weather/sun.svg"
        }
        if (type === "cloud") {
            return "qrc:/images/weather/cloud.svg"
        }
        if (type === "rain") {
            return "qrc:/images/weather/rain.svg"
        }
        if (type === "storm") {
            return "qrc:/images/weather/storm.svg"
        }
        return "qrc:/images/weather/partly.svg"
    }

    function accentColorForType(type) {
        if (type === "sun") {
            return "#ffcb57"
        }
        if (type === "cloud") {
            return "#b2c8e2"
        }
        if (type === "rain") {
            return "#72cbff"
        }
        if (type === "storm") {
            return "#ff9a63"
        }
        return "#f2c76b"
    }

    Component.onCompleted: {
        if (NavigationFeed.hasPositionFix) {
            Weather.setVehiclePosition(NavigationFeed.currentLatitude, NavigationFeed.currentLongitude)
        }
    }

    Connections {
        target: NavigationFeed
        function onPositionUpdated(latitude, longitude, speedKmh, headingDeg, timestampMs) {
            Weather.setVehiclePosition(latitude, longitude)
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 20

        Rectangle {
            width: Math.min(184, locationText.implicitWidth + 28)
            height: 30
            radius: 15
            color: Qt.rgba(0.05, 0.07, 0.10, 0.30)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            Row {
                anchors.centerIn: parent
                spacing: 6

                Image {
                    source: "qrc:/images/weather/location.svg"
                    width: 12
                    height: 12
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: locationText
                    width: Math.min(144, implicitWidth)
                    text: weatherRoot.resolvedCityName
                    color: Style.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            id: contentArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 26
            anchors.bottomMargin: 18

            Item {
                width: 120
                height: 120
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -8

                Image {
                    visible: weatherRoot.iconType === "partly"
                    source: "qrc:/images/weather/sun.svg"
                    width: 42
                    height: 42
                    x: 62
                    y: 6
                    fillMode: Image.PreserveAspectFit
                }

                Image {
                    source: weatherRoot.iconType === "partly"
                            ? "qrc:/images/weather/cloud.svg"
                            : weatherRoot.iconSourceForType(weatherRoot.iconType)
                    width: weatherRoot.iconType === "sun" ? 56 : 82
                    height: weatherRoot.iconType === "sun" ? 56 : 82
                    x: weatherRoot.iconType === "partly" ? 14 : 18
                    y: weatherRoot.iconType === "partly" ? 30 : 20
                    fillMode: Image.PreserveAspectFit
                }
            }

            Column {
                width: parent.width - 178
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 18
                spacing: 6

                Row {
                    spacing: 4

                    Text {
                        text: weatherRoot.loading ? "--" : weatherRoot.currentTemp
                        color: Style.textPrimary
                        font.pixelSize: 76
                        font.bold: true
                    }

                    Text {
                        text: "\u00B0C"
                        color: Style.textPrimary
                        font.pixelSize: 32
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -10
                        opacity: weatherRoot.loading ? 0.40 : 1.0
                    }
                }

                Text {
                    width: parent.width
                    text: weatherRoot.resolvedCondition
                    color: "#d9e8f5"
                    font.pixelSize: 22
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }
    }
}
