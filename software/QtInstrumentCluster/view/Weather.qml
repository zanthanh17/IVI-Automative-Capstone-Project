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
                                               ? "Updating…"
                                               : (conditionText.length > 0 ? conditionText : "--")

    // Parse detailText ("Feels like 28°C | Humidity 72%") into two parts
    readonly property string feelsLikeText: {
        if (!detailText || detailText.length === 0) return ""
        var parts = detailText.split("|")
        var s = parts[0].trim()
        // Strip "Feels like " prefix for compact display
        if (s.indexOf("Feels like") === 0) return s.replace("Feels like ", "")
        return s
    }
    readonly property string humidityText: {
        if (!detailText || detailText.length === 0) return ""
        var parts = detailText.split("|")
        if (parts.length < 2) return ""
        var s = parts[1].trim()
        if (s.indexOf("Humidity") === 0) return s.replace("Humidity ", "")
        return s
    }

    function iconSourceForType(type) {
        if (type === "sun")   return "qrc:/images/weather/sun.svg"
        if (type === "cloud") return "qrc:/images/weather/cloud.svg"
        if (type === "rain")  return "qrc:/images/weather/rain.svg"
        if (type === "storm") return "qrc:/images/weather/storm.svg"
        return "qrc:/images/weather/partly.svg"
    }

    function accentColorForType(type) {
        if (type === "sun")   return "#ffcb57"
        if (type === "cloud") return "#b2c8e2"
        if (type === "rain")  return "#72cbff"
        if (type === "storm") return "#ff9a63"
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

    // ── Root content ─────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 16

        // ── Location pill ────────────────────────────────────────────
        Rectangle {
            id: locationPill
            anchors.top: parent.top
            anchors.left: parent.left
            width: Math.min(200, locationPillRow.implicitWidth + 24)
            height: 28
            radius: 14
            color: Qt.rgba(0.05, 0.07, 0.10, 0.38)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.13)

            Row {
                id: locationPillRow
                anchors.centerIn: parent
                spacing: 6

                Image {
                    source: "qrc:/images/weather/location.svg"
                    width: 11
                    height: 11
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    width: Math.min(156, implicitWidth)
                    text: weatherRoot.resolvedCityName
                    color: Style.textPrimary
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Last updated pill ─────────────────────────────────────────
        Rectangle {
            id: updatedPill
            anchors.top: parent.top
            anchors.right: parent.right
            visible: weatherRoot.lastUpdated.length > 0 && !weatherRoot.loading
            width: updatedText.implicitWidth + 20
            height: 28
            radius: 14
            color: Qt.rgba(0.05, 0.07, 0.10, 0.38)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Text {
                id: updatedText
                anchors.centerIn: parent
                text: "Updated " + weatherRoot.lastUpdated
                color: "#6b7280"
                font.pixelSize: 10
            }
        }

        // ── Main content area ─────────────────────────────────────────
        Item {
            id: mainContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: locationPill.bottom
            anchors.bottom: detailRow.top
            anchors.topMargin: 8
            anchors.bottomMargin: 8

            // Loading spinner overlay
            Item {
                anchors.fill: parent
                visible: weatherRoot.loading

                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.15)

                    Rectangle {
                        width: 4
                        height: 16
                        radius: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        color: weatherRoot.accentColor
                        opacity: 0.9

                        RotationAnimator {
                            target: parent.parent
                            running: weatherRoot.loading
                            from: 0; to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 20
                    text: "Fetching weather…"
                    color: "#6b7280"
                    font.pixelSize: 13
                }
            }

            // Error state
            Item {
                anchors.fill: parent
                visible: weatherRoot.offline && !weatherRoot.loading

                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -8
                    spacing: 12

                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: Qt.rgba(1.0, 0.35, 0.25, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(1.0, 0.35, 0.25, 0.30)
                        anchors.horizontalCenter: parent.horizontalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: "#ff7b6b"
                            font.pixelSize: 24
                            font.bold: true
                        }
                    }

                    Text {
                        width: 260
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: weatherRoot.weatherError.length > 40
                              ? weatherRoot.weatherError.substring(0, 40) + "…"
                              : weatherRoot.weatherError
                        color: "#9ca3af"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    // Retry button
                    Rectangle {
                        width: 88
                        height: 32
                        radius: 16
                        color: retryArea.pressed ? Qt.rgba(0.33, 0.56, 1.0, 0.22) : Qt.rgba(0.33, 0.56, 1.0, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(0.33, 0.56, 1.0, 0.40)
                        anchors.horizontalCenter: parent.horizontalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "Retry"
                            color: "#8ab4ff"
                            font.pixelSize: 12
                            font.bold: true
                        }

                        MouseArea {
                            id: retryArea
                            anchors.fill: parent
                            onClicked: Weather.refresh()
                        }
                    }
                }
            }

            // Normal weather display
            Item {
                anchors.fill: parent
                visible: !weatherRoot.loading && !weatherRoot.offline

                // Weather icon (right side)
                Item {
                    id: iconArea
                    width: 110
                    height: 110
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -6

                    // Partly cloudy: sun behind cloud
                    Image {
                        visible: weatherRoot.iconType === "partly"
                        source: "qrc:/images/weather/sun.svg"
                        width: 44
                        height: 44
                        x: 56
                        y: 4
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.9
                    }

                    Image {
                        source: weatherRoot.iconType === "partly"
                                ? "qrc:/images/weather/cloud.svg"
                                : weatherRoot.iconSourceForType(weatherRoot.iconType)
                        width: weatherRoot.iconType === "sun" ? 60 : 82
                        height: weatherRoot.iconType === "sun" ? 60 : 82
                        x: weatherRoot.iconType === "partly" ? 10 : 14
                        y: weatherRoot.iconType === "partly" ? 28 : 16
                        fillMode: Image.PreserveAspectFit
                    }
                }

                // Temperature + condition (left side)
                Column {
                    anchors.left: parent.left
                    anchors.right: iconArea.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 14
                    spacing: 4

                    // Temperature row
                    Row {
                        spacing: 3

                        Text {
                            text: weatherRoot.loading ? "--" : weatherRoot.currentTemp
                            color: Style.textPrimary
                            font.pixelSize: 72
                            font.bold: true
                        }

                        Text {
                            text: "°C"
                            color: Style.textPrimary
                            font.pixelSize: 30
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -12
                            opacity: weatherRoot.loading ? 0.35 : 0.85
                        }
                    }

                    // Condition text
                    Text {
                        width: parent.width
                        text: weatherRoot.resolvedCondition
                        color: weatherRoot.accentColor
                        font.pixelSize: 18
                        font.bold: true
                        elide: Text.ElideRight

                        Behavior on color { ColorAnimation { duration: 400 } }
                    }
                }
            }
        }

        // ── Detail info row (Feels like + Humidity) ───────────────────
        Row {
            id: detailRow
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8
            visible: weatherRoot.feelsLikeText.length > 0 || weatherRoot.humidityText.length > 0

            // Feels like chip
            Rectangle {
                visible: weatherRoot.feelsLikeText.length > 0
                width: (parent.width - parent.spacing) / 2
                height: 36
                radius: 10
                color: Qt.rgba(0.05, 0.07, 0.10, 0.45)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Feels like"
                        color: "#6b7280"
                        font.pixelSize: 9
                        font.letterSpacing: 0.4
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: weatherRoot.feelsLikeText
                        color: "#d1d5db"
                        font.pixelSize: 13
                        font.bold: true
                    }
                }
            }

            // Humidity chip
            Rectangle {
                visible: weatherRoot.humidityText.length > 0
                width: (parent.width - parent.spacing) / 2
                height: 36
                radius: 10
                color: Qt.rgba(0.05, 0.07, 0.10, 0.45)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Humidity"
                        color: "#6b7280"
                        font.pixelSize: 9
                        font.letterSpacing: 0.4
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: weatherRoot.humidityText
                        color: "#d1d5db"
                        font.pixelSize: 13
                        font.bold: true
                    }
                }
            }
        }
    }
}
