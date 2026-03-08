import QtQuick 2.12
import QtLocation 6.2
import QtPositioning 6.2
import NavigationModel 1.0
import NavigationFeed 1.0
import OsrmRoute 1.0

Item {
    id: navMapRoot

    /*
     * CartoDB Dark Matter tiles: free, beautiful dark theme, HiDPI support
     * No API key required. Perfect for automotive dashboard.
     */
    property string darkTileHost: "https://basemaps.cartocdn.com/dark_all/%z/%x/%y@2x.png"
    property string destinationSearchText: "Cau Rong, Da Nang, Vietnam"
    property var destinationCoordinate: QtPositioning.coordinate(16.05200, 108.21870)
    property bool liveRouteReady: false

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

    function rebuildRouteFromActiveSource() {
        if (liveRouteReady && OsrmRoute.routePath.length > 1) {
            routePath = OsrmRoute.routePath
            updateSegmentedPath()
            return
        }

        routePath = buildRoutePath()
        updateSegmentedPath()
    }

    function requestRouteToDestination() {
        var origin = QtPositioning.coordinate(NavigationFeed.currentLatitude, NavigationFeed.currentLongitude)
        if (!origin.isValid || !destinationCoordinate || !destinationCoordinate.isValid) {
            return
        }

        OsrmRoute.requestRoute(
            origin.latitude, origin.longitude,
            destinationCoordinate.latitude, destinationCoordinate.longitude
        )
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

        for (var i = 0; i < navMap.supportedMapTypes.length; ++i) {
            var mt = navMap.supportedMapTypes[i]
            if (mt.style === MapType.CustomMap) {
                navMap.activeMapType = mt
                return
            }
        }

        for (var j = 0; j < navMap.supportedMapTypes.length; ++j) {
            var fallback = navMap.supportedMapTypes[j]
            var text = ((fallback.name || "") + " " + (fallback.description || "")).toLowerCase()
            if (text.indexOf("dark") >= 0 || text.indexOf("night") >= 0 || text.indexOf("navigation") >= 0) {
                navMap.activeMapType = fallback
                return
            }
        }

        if (navMap.supportedMapTypes.length > 0) {
            navMap.activeMapType = navMap.supportedMapTypes[0]
        }
    }

    Component.onCompleted: {
        rebuildRouteFromActiveSource()
        applyPreferredMapType()
        requestRouteToDestination()
    }

    Connections {
        target: NavigationModel
        function onRouteProgressChanged() { navMapRoot.updateSegmentedPath() }
    }

    Connections {
        target: OsrmRoute
        function onRouteReady(path) {
            navMapRoot.liveRouteReady = true
            navMapRoot.rebuildRouteFromActiveSource()
        }
        function onRouteFailed(error) {
            console.warn("OSRM routing failed:", error)
            navMapRoot.liveRouteReady = false
            navMapRoot.rebuildRouteFromActiveSource()
        }
    }

    /*
     * OSM plugin with CartoDB Dark Matter tiles
     * Free, no API key, beautiful dark theme with HiDPI @2x tiles
     * Routing via OSRM HTTP API (OsrmRouteProvider C++)
     */
    Plugin {
        id: darkMapPlugin
        name: "osm"
        PluginParameter { name: "osm.useragent"; value: "QtInstrumentCluster/1.0" }
        PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
        PluginParameter { name: "osm.mapping.highdpi_tiles"; value: true }
        PluginParameter { name: "osm.mapping.custom.host"; value: navMapRoot.darkTileHost }
        PluginParameter { name: "osm.mapping.custom.mapcopyright"; value: "CartoDB" }
        PluginParameter { name: "osm.mapping.custom.datacopyright"; value: "OpenStreetMap contributors" }
    }

    /* Invisible container – same size as other menu pages content area */
    Item {
        id: mapArea
        anchors.horizontalCenter: parent.horizontalCenter
        y: 82
        width: 392
        height: 286
        clip: true

        Map {
            id: navMap
            anchors.fill: parent
            plugin: darkMapPlugin
            color: "#00091a"
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
    }

    /* Floating mini-guide overlay */
    Row {
        id: topMiniGuide
        anchors.left: mapArea.left
        anchors.leftMargin: 10
        anchors.top: mapArea.top
        anchors.topMargin: 10
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
            }
            Text {
                text: navMapRoot.maneuverVerb(NavigationModel.maneuver)
                color: "#99b4cf"
                font.pixelSize: 10
            }
        }
    }

    /* Floating guide panel overlay */
    Column {
        id: guidePanel
        anchors.left: mapArea.left
        anchors.right: mapArea.right
        anchors.bottom: mapArea.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: 6
        spacing: 6

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
            }

            Item { width: 1; height: 1 }

            Text {
                text: navMapRoot.maneuverVerb(NavigationModel.maneuver)
                color: "#a7c0d8"
                font.pixelSize: 12
            }
        }

        Row {
            spacing: 8

            Text {
                text: "THEN"
                color: "#6f8499"
                font.pixelSize: 10
                font.bold: true
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
            }

            Text {
                property real nextDistance: (NavigationModel.currentStep + 1 < NavigationModel.route.length)
                                            ? NavigationModel.route[NavigationModel.currentStep + 1].dist
                                            : 0
                text: nextDistance > 0 ? ("in " + navMapRoot.formatMeters(nextDistance)) : ""
                color: "#8ea4bb"
                font.pixelSize: 12
            }
        }
    }
}


