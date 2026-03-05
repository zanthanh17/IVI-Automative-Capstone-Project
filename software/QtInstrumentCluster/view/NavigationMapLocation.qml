import QtQuick 2.12
import QtLocation 6.2
import QtPositioning 6.2
import NavigationModel 1.0
import NavigationFeed 1.0

Item {
    id: navMapRoot

    property var routePath: []
    property var pastPath: []
    property var mainPath: []
    property var cautionPath: []
    property var finalPath: []

    function formatMeters(meters) {
        if (meters >= 1000) {
            return (meters / 1000).toFixed(1) + " km"
        }
        return Math.round(Math.max(0, meters)) + " m"
    }

    function buildRoutePath() {
        var list = []
        var raw = NavigationFeed.mockRoute
        if (raw.length === 0) {
            return list
        }

        for (var i = 0; i < raw.length - 1; ++i) {
            var from = raw[i]
            var to = raw[i + 1]
            list.push(QtPositioning.coordinate(from.lat, from.lon))
            for (var step = 1; step <= 6; ++step) {
                var t = step / 7.0
                var lat = from.lat + (to.lat - from.lat) * t
                var lon = from.lon + (to.lon - from.lon) * t
                list.push(QtPositioning.coordinate(lat, lon))
            }
        }

        list.push(QtPositioning.coordinate(raw[raw.length - 1].lat, raw[raw.length - 1].lon))
        return list
    }

    function subPath(startIndex, endIndex) {
        var list = []
        if (routePath.length < 2) {
            return list
        }

        var start = Math.max(0, Math.min(startIndex, routePath.length - 1))
        var end = Math.max(0, Math.min(endIndex, routePath.length - 1))
        if (end < start) {
            var tmp = start
            start = end
            end = tmp
        }
        for (var i = start; i <= end; ++i) {
            list.push(routePath[i])
        }
        return list
    }

    function updateSegmentedPath() {
        if (routePath.length < 2) {
            pastPath = []
            mainPath = []
            cautionPath = []
            finalPath = []
            return
        }

        var last = routePath.length - 1
        var currentIndex = Math.floor(Math.max(0, Math.min(1, NavigationModel.routeProgress)) * last)
        var mainEnd = Math.min(last, currentIndex + Math.max(10, Math.floor((last - currentIndex) * 0.55)))
        var cautionEnd = Math.min(last, mainEnd + Math.max(6, Math.floor((last - mainEnd) * 0.60)))

        pastPath = subPath(0, currentIndex)
        mainPath = subPath(currentIndex, mainEnd)
        cautionPath = subPath(mainEnd, cautionEnd)
        finalPath = subPath(cautionEnd, last)
    }

    function maneuverVerb(value) {
        if (value === NavigationModel.TurnLeft) {
            return "turn left"
        }
        if (value === NavigationModel.TurnRight) {
            return "turn right"
        }
        if (value === NavigationModel.GoStraight) {
            return "go straight"
        }
        if (value === NavigationModel.UTurn) {
            return "make a U-turn"
        }
        return "arrive"
    }

    function drawArrow(ctx, maneuver, color) {
        ctx.reset()
        ctx.lineWidth = 2.8
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        if (maneuver === NavigationModel.TurnRight) {
            ctx.beginPath()
            ctx.moveTo(4, 24)
            ctx.lineTo(4, 10)
            ctx.lineTo(20, 10)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(14, 4)
            ctx.lineTo(26, 10)
            ctx.lineTo(14, 17)
            ctx.fill()
        } else if (maneuver === NavigationModel.TurnLeft) {
            ctx.beginPath()
            ctx.moveTo(26, 24)
            ctx.lineTo(26, 10)
            ctx.lineTo(10, 10)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(16, 4)
            ctx.lineTo(4, 10)
            ctx.lineTo(16, 17)
            ctx.fill()
        } else if (maneuver === NavigationModel.UTurn) {
            ctx.beginPath()
            ctx.moveTo(18, 24)
            ctx.lineTo(18, 8)
            ctx.arc(12, 8, 6, 0, Math.PI, true)
            ctx.lineTo(6, 14)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(3, 9)
            ctx.lineTo(8, 14)
            ctx.lineTo(13, 9)
            ctx.fill()
        } else if (maneuver === NavigationModel.Arrive) {
            ctx.beginPath()
            ctx.arc(15, 10, 6, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(15, 10, 3, 0, Math.PI * 2)
            ctx.fill()
        } else {
            ctx.beginPath()
            ctx.moveTo(15, 25)
            ctx.lineTo(15, 8)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(8, 14)
            ctx.lineTo(15, 4)
            ctx.lineTo(22, 14)
            ctx.fill()
        }
    }

    function applyPreferredMapType() {
        if (!navMap.supportedMapTypes || navMap.supportedMapTypes.length === 0) {
            return
        }

        var bestIndex = -1
        for (var i = 0; i < navMap.supportedMapTypes.length; ++i) {
            var mt = navMap.supportedMapTypes[i]
            var text = ((mt.name || "") + " " + (mt.description || "")).toLowerCase()
            if (text.indexOf("dark") >= 0 || text.indexOf("night") >= 0 || text.indexOf("gray") >= 0) {
                bestIndex = i
                break
            }
        }

        if (bestIndex < 0) {
            for (var j = 0; j < navMap.supportedMapTypes.length; ++j) {
                var fallback = navMap.supportedMapTypes[j]
                var fallbackText = ((fallback.name || "") + " " + (fallback.description || "")).toLowerCase()
                if (fallbackText.indexOf("navigation") >= 0) {
                    bestIndex = j
                    break
                }
            }
        }

        if (bestIndex >= 0) {
            navMap.activeMapType = navMap.supportedMapTypes[bestIndex]
        }
    }

    Component.onCompleted: {
        routePath = buildRoutePath()
        updateSegmentedPath()
        applyPreferredMapType()
    }

    Connections {
        target: NavigationModel
        function onRouteProgressChanged() { navMapRoot.updateSegmentedPath() }
    }

    Plugin {
        id: osmPlugin
        name: "osm"
    }

    Rectangle {
        id: mapShell
        anchors.horizontalCenter: parent.horizontalCenter
        y: 82
        width: 392
        height: 286
        radius: 18
        color: "#0a1322"
        border.width: 1
        border.color: "#2f70be"
        clip: true

        Map {
            id: navMap
            anchors.fill: parent
            anchors.margins: 1
            plugin: osmPlugin
            color: "#0a0f16"
            zoomLevel: 16.8
            tilt: 50
            bearing: NavigationFeed.currentHeadingDeg
            center: QtPositioning.coordinate(NavigationFeed.currentLatitude, NavigationFeed.currentLongitude)
            onSupportedMapTypesChanged: navMapRoot.applyPreferredMapType()

            MapPolyline {
                line.width: 7
                line.color: "#1e3247"
                path: navMapRoot.pastPath
                smooth: true
                opacity: 0.88
            }

            MapPolyline {
                line.width: 11
                line.color: "#19395b"
                path: navMapRoot.mainPath
                smooth: true
            }

            MapPolyline {
                line.width: 7
                line.color: "#7ef2d0"
                path: navMapRoot.mainPath
                smooth: true
            }

            MapPolyline {
                line.width: 7
                line.color: "#f7df65"
                path: navMapRoot.cautionPath
                smooth: true
            }

            MapPolyline {
                line.width: 7
                line.color: "#ff7665"
                path: navMapRoot.finalPath
                smooth: true
            }

            MapQuickItem {
                coordinate: QtPositioning.coordinate(NavigationFeed.currentLatitude, NavigationFeed.currentLongitude)
                anchorPoint.x: marker.width / 2
                anchorPoint.y: marker.height / 2

                sourceItem: Item {
                    id: marker
                    width: 34
                    height: 34

                    Rectangle {
                        anchors.centerIn: parent
                        width: 34
                        height: 34
                        radius: 17
                        color: "#2294f4"
                        border.width: 1
                        border.color: "#8bd0ff"
                    }

                    Canvas {
                        anchors.centerIn: parent
                        width: 13
                        height: 13
                        rotation: NavigationFeed.currentHeadingDeg
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = "#f3fbff"
                            ctx.beginPath()
                            ctx.moveTo(6.5, 0)
                            ctx.lineTo(13, 13)
                            ctx.lineTo(6.5, 10)
                            ctx.lineTo(0, 13)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#060b11"
            opacity: 0.38
        }

        Rectangle {
            id: topMiniGuide
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.top: parent.top
            anchors.topMargin: 12
            width: 170
            height: 42
            radius: 10
            color: "#111a27"
            border.width: 1
            border.color: "#2f6fbe"
            opacity: 0.92

            Row {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 8
                spacing: 8

                Canvas {
                    width: 28
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: navMapRoot.drawArrow(getContext("2d"), NavigationModel.maneuver, "#7ef2d0")
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        text: NavigationModel.distanceToTurnText
                        color: "#f0f8ff"
                        font.pixelSize: 16
                        font.bold: true
                        font.family: "Sarabun"
                    }
                    Text {
                        text: navMapRoot.maneuverVerb(NavigationModel.maneuver)
                        color: "#99b4cf"
                        font.pixelSize: 10
                        font.family: "Sarabun"
                    }
                }
            }
        }

        Rectangle {
            id: guidePanel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.bottomMargin: 8
            height: 104
            radius: 14
            color: "#08111c"
            border.width: 1
            border.color: "#1f3d5d"
            opacity: 0.96

            Column {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 8

                Row {
                    spacing: 8

                    Canvas {
                        width: 24
                        height: 24
                        onPaint: navMapRoot.drawArrow(getContext("2d"), NavigationModel.maneuver, "#7ef2d0")
                    }

                    Text {
                        text: NavigationModel.nextStreet.length > 0 ? NavigationModel.nextStreet : NavigationModel.currentStreet
                        color: "#f0f8ff"
                        font.pixelSize: 16
                        font.bold: true
                        font.family: "Sarabun"
                    }

                    Item { width: 1; height: 1 }

                    Text {
                        text: navMapRoot.maneuverVerb(NavigationModel.maneuver)
                        color: "#a7c0d8"
                        font.pixelSize: 12
                        font.family: "Sarabun"
                    }
                }

                Row {
                    spacing: 8

                    Text {
                        text: "THEN"
                        color: "#6f8499"
                        font.pixelSize: 10
                        font.bold: true
                        font.family: "Sarabun"
                    }

                    Canvas {
                        width: 20
                        height: 20
                        property int nextManeuver: (NavigationModel.currentStep + 1 < NavigationModel.route.length)
                                                   ? NavigationModel.route[NavigationModel.currentStep + 1].maneuver
                                                   : NavigationModel.Arrive
                        onPaint: navMapRoot.drawArrow(getContext("2d"), nextManeuver, "#7ea8ec")
                    }

                    Text {
                        property string nextStreet: (NavigationModel.currentStep + 1 < NavigationModel.route.length)
                                                    ? NavigationModel.route[NavigationModel.currentStep + 1].next
                                                    : "Destination"
                        text: nextStreet
                        color: "#8ea4bb"
                        font.pixelSize: 13
                        font.family: "Sarabun"
                    }

                    Text {
                        property real nextDistance: (NavigationModel.currentStep + 1 < NavigationModel.route.length)
                                                    ? NavigationModel.route[NavigationModel.currentStep + 1].dist
                                                    : 0
                        text: nextDistance > 0 ? ("in " + navMapRoot.formatMeters(nextDistance)) : ""
                        color: "#8ea4bb"
                        font.pixelSize: 12
                        font.family: "Sarabun"
                    }
                }
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 372
        text: NavigationFeed.useMockGps ? "GPS source: MOCK" : "GPS source: HARDWARE"
        font.pixelSize: 10
        font.family: "Sarabun"
        color: "#5d9ae2"
        opacity: 0.82
    }
}
