import QtQuick 2.12
import Weather 1.0
import Style 1.0

NormalModeContentItem {
    id: weatherRoot

    property string cityName: Weather.cityName
    property int currentTemp: Weather.temperature
    property string conditionText: Weather.conditionText
    property string iconType: Weather.iconType
    property string lastUpdated: Weather.lastUpdated
    property bool loading: Weather.loading
    property string weatherError: Weather.errorString

    function iconSourceForType(type) {
        // Mapping iconType từ API → bộ icon Tesla (PNG) trong qrc
        var base = "qrc:/images/weather/icons/"
        var t = (type || "").toLowerCase()

        if (t.indexOf("thunder") !== -1)      return base + "weather-thundershower.png"
        if (t.indexOf("sleet") !== -1)        return base + "weather-sleet.png"
        if (t.indexOf("snow") !== -1)         return base + "weather-snow.png"
        if (t.indexOf("storm") !== -1)        return base + "weather-storm.png"
        if (t.indexOf("shower") !== -1 ||
            t.indexOf("rain") !== -1 ||
            t.indexOf("drizzle") !== -1)      return base + "weather-showers.png"

        if (t.indexOf("overcast") !== -1)     return base + "weather-overcast.png"
        if (t.indexOf("few clouds") !== -1 ||
            t.indexOf("few-clouds") !== -1 ||
            t.indexOf("partly") !== -1)       return base + "weather-sunny-very-few-clouds.png"

        if (t.indexOf("fog") !== -1 ||
            t.indexOf("mist") !== -1)         return base + "weather-fog.png"
        if (t.indexOf("haze") !== -1)         return base + "weather-haze.png"
        if (t.indexOf("ice") !== -1 ||
            t.indexOf("icy") !== -1)          return base + "weather-icy.png"

        if (t.indexOf("cloud") !== -1)        return base + "weather-few-clouds.png"
        if (t === "" ||
            t.indexOf("clear") !== -1 ||
            t.indexOf("sun") !== -1)          return base + "weather-sunny.png"

        // fallback chung
        return base + "weather-overcast.png"
    }

    Component.onCompleted: {
        Weather.refresh()
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 22

        /* === City & Location === */
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            Image {
                source: "qrc:/images/weather/location.svg"
                width: 14
                height: 14
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: weatherRoot.cityName
                color: Style.textPrimary
                font.pixelSize: 16
                font.bold: true
            }
        }

        /* === Last Updated === */
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: weatherRoot.lastUpdated.length > 0 ? ("Updated " + weatherRoot.lastUpdated) : ""
            color: Style.textSecondary
            font.pixelSize: 10
        }

        /* === Temperature and Weather Icon === */
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 32

            Row {
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: weatherRoot.loading ? "--" : weatherRoot.currentTemp
                    color: Style.textPrimary
                    font.pixelSize: 56
                    font.bold: true
                }

                Text {
                    text: "\u00B0C"
                    color: Style.textSecondary
                    font.pixelSize: 30
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 8
                    opacity: weatherRoot.loading ? 0.35 : 1.0
                }
            }

            Rectangle {
                id: iconCard
                width: 86
                height: 86
                radius: 26
                color: Style.backgroundPanelSoft
                border.width: 0

                Image {
                    id: weatherIcon
                    anchors.centerIn: parent
                    width: 64
                    height: 64
                    source: weatherRoot.iconSourceForType(weatherRoot.iconType)
                    fillMode: Image.PreserveAspectFit
                }
            }
        }

        /* === Condition Text === */
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: weatherRoot.conditionText
            color: Style.textSecondary
            font.pixelSize: 14
        }

        /* === Error hint === */
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: weatherRoot.weatherError.length > 0
            text: "Weather offline"
            color: "#ef9a9a"
            font.pixelSize: 10
            opacity: 0.6
        }
    }
}
