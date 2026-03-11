import QtQuick 2.12
import Weather 1.0

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

    Rectangle {
        id: weatherCard
        width: 318
        height: 156
        radius: 14
        anchors.horizontalCenter: parent.horizontalCenter
        y: 138
        color: "#0b1523"
        border.width: 1
        border.color: "#224a73"
        clip: true

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#163755" }
            GradientStop { position: 0.46; color: "#0f263d" }
            GradientStop { position: 1.0; color: "#09131f" }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: weatherCard.radius - 1
            color: "#18060d17"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 44
            color: "transparent"

            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1f4c75" }
                GradientStop { position: 1.0; color: "#001f3d00" }
            }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 11
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
                font.pixelSize: 14
                font.family: "Sarabun"
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 30
            text: weatherRoot.lastUpdated.length > 0 ? ("Updated " + weatherRoot.lastUpdated) : ""
            color: "#8198af"
            font.pixelSize: 9
            font.family: "Sarabun"
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 42
            spacing: 2

            Text {
                text: weatherRoot.loading ? "--" : weatherRoot.currentTemp
                color: "#f5fbff"
                font.pixelSize: 50
                font.bold: true
                font.family: "Sarabun"
            }

            Text {
                text: "\u00B0C"
                color: "#f5fbff"
                font.pixelSize: 28
                font.bold: true
                font.family: "Sarabun"
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 8
                opacity: weatherRoot.loading ? 0.35 : 1.0
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 116
            text: weatherRoot.conditionText
            color: "#9eb7cf"
            font.pixelSize: 14
            font.family: "Sarabun"
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            visible: weatherRoot.weatherError.length > 0
            text: "Weather offline"
            color: "#ef9a9a"
            font.pixelSize: 9
            font.family: "Sarabun"
        }

        Item {
            id: weatherIcon
            width: 108
            height: 108
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.top: parent.top
            anchors.topMargin: 8

            Image {
                visible: weatherRoot.iconType === "partly"
                source: "qrc:/images/weather/sun.svg"
                width: 52
                height: 52
                x: 42
                y: 8
                fillMode: Image.PreserveAspectFit
            }

            Image {
                source: weatherRoot.iconType === "partly"
                        ? "qrc:/images/weather/cloud.svg"
                        : weatherRoot.iconSourceForType(weatherRoot.iconType)
                width: weatherRoot.iconType === "sun" ? 76 : 86
                height: weatherRoot.iconType === "sun" ? 76 : 86
                x: weatherRoot.iconType === "partly" ? 12 : 10
                y: weatherRoot.iconType === "partly" ? 24 : 14
                fillMode: Image.PreserveAspectFit
            }
        }
    }
}
