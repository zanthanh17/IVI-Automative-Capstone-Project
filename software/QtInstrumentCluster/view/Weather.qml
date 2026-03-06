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

    Component.onCompleted: {
        Weather.refresh()
    }

    /* === City & Location === */
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 110
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
            color: "#d6ebff"
            font.pixelSize: 16
            font.bold: true
        }
    }

    /* === Last Updated === */
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 134
        text: weatherRoot.lastUpdated.length > 0 ? ("Updated " + weatherRoot.lastUpdated) : ""
        color: "#8198af"
        font.pixelSize: 10
    }

    /* === Temperature and Weather Icon === */
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 155
        spacing: 30

        Row {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: weatherRoot.loading ? "--" : weatherRoot.currentTemp
                color: Style.lightPeriwinkle
                font.pixelSize: 56
                font.bold: true
            }

            Text {
                text: "\u00B0C"
                color: Style.lightPeriwinkle
                font.pixelSize: 30
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 8
                opacity: weatherRoot.loading ? 0.35 : 1.0
            }
        }

        Item {
            id: weatherIcon
            width: 80
            height: 80
            anchors.verticalCenter: parent.verticalCenter

            Image {
                visible: weatherRoot.iconType === "partly"
                source: "qrc:/images/weather/sun.svg"
                width: 40
                height: 40
                x: 30
                y: 4
                fillMode: Image.PreserveAspectFit
            }

            Image {
                source: weatherRoot.iconType === "partly"
                        ? "qrc:/images/weather/cloud.svg"
                        : weatherRoot.iconSourceForType(weatherRoot.iconType)
                width: weatherRoot.iconType === "sun" ? 60 : 70
                height: weatherRoot.iconType === "sun" ? 60 : 70
                x: weatherRoot.iconType === "partly" ? 0 : 5
                y: weatherRoot.iconType === "partly" ? 16 : 6
                fillMode: Image.PreserveAspectFit
            }
        }
    }

    /* === Condition Text === */
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 233
        text: weatherRoot.conditionText
        color: "#9eb7cf"
        font.pixelSize: 14
    }

    /* === Error hint === */
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 260
        visible: weatherRoot.weatherError.length > 0
        text: "Weather offline"
        color: "#ef9a9a"
        font.pixelSize: 10
        opacity: 0.6
    }
}
