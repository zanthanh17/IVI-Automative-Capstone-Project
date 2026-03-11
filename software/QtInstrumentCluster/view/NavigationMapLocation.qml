import QtQuick 2.12
import QtQuick.Controls 2.12
import QtLocation 5.15
import QtPositioning 5.15
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
    property string destinationSearchText: ""
    property var destinationCoordinate: QtPositioning.coordinate()
    property bool searchPanelVisible: false
    property bool liveRouteReady: false
    property int osrmRetryCount: 0
    readonly property int osrmMaxRetries: 2
    property real rerouteThresholdMeters: 45
    property int rerouteCooldownMs: 8000
    property double lastRouteRequestMs: 0

    property var routePath: []
    property var pastPath: []
    property var mainPath: []
    property var cautionPath: []
    property var finalPath: []

    function hasVehicleFix() {
        return NavigationFeed.hasPositionFix
               && Number.isFinite(NavigationFeed.currentLatitude)
               && Number.isFinite(NavigationFeed.currentLongitude)
    }

    function vehicleCoordinate() {
        if (!hasVehicleFix()) {
            return QtPositioning.coordinate()
        }
        return QtPositioning.coordinate(NavigationFeed.currentLatitude, NavigationFeed.currentLongitude)
    }

    function formatMeters(meters) {
        if (meters >= 1000) {
            return (meters / 1000).toFixed(1) + " km"
        }
        return Math.round(Math.max(0, meters)) + " m"
    }

    function formatDurationSeconds(seconds) {
        var mins = Math.max(1, Math.round(seconds / 60))
        if (mins >= 60) {
            var h = Math.floor(mins / 60)
            var m = mins % 60
            return h + "h " + m + "m"
        }
        return mins + " min"
    }

    function triggerDestinationSearch() {
        var q = destinationSearchText.trim()
        if (q.length < 3) {
            searchPanelVisible = false
            return
        }
        destinationGeocode.query = q
        destinationGeocode.update()
    }

    function chooseDestinationFromResult(resultAddress, resultCoordinate) {
        if (!resultCoordinate || !resultCoordinate.isValid) {
            return
        }

        destinationCoordinate = resultCoordinate
        if (resultAddress && resultAddress.text) {
            destinationSearchText = resultAddress.text
        } else {
            destinationSearchText = resultCoordinate.latitude.toFixed(5) + ", " + resultCoordinate.longitude.toFixed(5)
        }

        searchPanelVisible = false
        liveRouteReady = false
        osrmRetryCount = 0
        requestRouteToDestination()
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

    function requestRouteToDestination(force) {
        force = !!force
        var origin = vehicleCoordinate()
        if (!origin.isValid || !destinationCoordinate || !destinationCoordinate.isValid) {
            return
        }
        if (OsrmRoute.busy) {
            return
        }
        var now = Date.now()
        if (!force && (now - lastRouteRequestMs) < rerouteCooldownMs) {
            return
        }
        lastRouteRequestMs = now

        OsrmRoute.requestRoute(
            origin.latitude, origin.longitude,
            destinationCoordinate.latitude, destinationCoordinate.longitude
        )
    }

    function nearestDistanceToRouteMeters(coord) {
        if (!coord || !coord.isValid || routePath.length === 0) {
            return Number.POSITIVE_INFINITY
        }
        var min = Number.POSITIVE_INFINITY
        for (var i = 0; i < routePath.length; ++i) {
            var p = routePath[i]
            if (!p || !p.isValid) {
                continue
            }
            var d = coord.distanceTo(p)
            if (d < min) {
                min = d
            }
        }
        return min
    }

    function maybeRerouteIfOffRoute() {
        if (!liveRouteReady || !hasVehicleFix() || !destinationCoordinate || !destinationCoordinate.isValid) {
            return
        }
        var current = vehicleCoordinate()
        var offRouteMeters = nearestDistanceToRouteMeters(current)
        if (offRouteMeters > rerouteThresholdMeters) {
            console.log("[NavMap] Off-route detected:", Math.round(offRouteMeters), "m. Requesting reroute.")
            requestRouteToDestination(true)
        }
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
        console.log("[NavMap] Route initialized with", routePath.length, "points")
    }

    Timer {
        id: osrmRetryTimer
        interval: 3000
        repeat: false
        onTriggered: {
            console.log("[NavMap] Retrying OSRM route request (attempt", navMapRoot.osrmRetryCount + 1, ")")
            navMapRoot.requestRouteToDestination(true)
        }
    }

    Timer {
        id: rerouteMonitor
        interval: 2000
        repeat: true
        running: navMapRoot.liveRouteReady
        onTriggered: navMapRoot.maybeRerouteIfOffRoute()
    }

    Connections {
        target: NavigationModel
        function onRouteProgressChanged() { navMapRoot.updateSegmentedPath() }
    }

    Connections {
        target: NavigationFeed
        function onPositionUpdated() {
            if (!navMapRoot.liveRouteReady) {
                navMapRoot.requestRouteToDestination()
            } else {
                navMapRoot.maybeRerouteIfOffRoute()
            }
        }
        function onRouteLooped() {
            console.log("[NavMap] Route looped, rebuilding path")
            navMapRoot.rebuildRouteFromActiveSource()
        }
    }

    Connections {
        target: OsrmRoute
        function onAlternativeRoutesChanged() {
            // Property binding handles UI refresh; this keeps debug visibility.
            console.log("[NavMap] Alternatives available:", OsrmRoute.alternativeRoutes.length)
        }
        function onSelectedRouteChanged() {
            navMapRoot.rebuildRouteFromActiveSource()
        }
        function onRouteReady(path) {
            console.log("[NavMap] OSRM route received with", path.length, "points")
            navMapRoot.osrmRetryCount = 0
            navMapRoot.liveRouteReady = true
            navMapRoot.rebuildRouteFromActiveSource()
        }
        function onRouteFailed(error) {
            console.warn("[NavMap] OSRM routing failed:", error)
            navMapRoot.liveRouteReady = false
            navMapRoot.rebuildRouteFromActiveSource()
            if (navMapRoot.osrmRetryCount < navMapRoot.osrmMaxRetries) {
                navMapRoot.osrmRetryCount++
                osrmRetryTimer.restart()
            }
        }
    }

    /*
     * Mapbox GL native plugin — requires access token
     * Uses navigation-night-v1: a classic dark automotive-friendly style
     * fully compatible with mapbox-gl-native (Qt5).
     * Note: Custom styles with Mapbox Standard imports are NOT supported.
     * Route rendering via OSRM HTTP API (OsrmRouteProvider C++)
     */
    // Token is injected from main.cpp via QML context property: mapboxTokenFromEnv
    // Set before running: export MAPBOX_ACCESS_TOKEN="pk.eyJ1..."

    Plugin {
        id: darkMapPlugin
        name: "mapboxgl"
        PluginParameter { name: "mapboxgl.access_token"; value: mapboxTokenFromEnv }
        PluginParameter { name: "mapboxgl.mapping.additional_style_urls"; value: "mapbox://styles/mapbox/navigation-night-v1" }
    }

    GeocodeModel {
        id: destinationGeocode
        plugin: darkMapPlugin
        autoUpdate: false
        limit: 6
        onStatusChanged: {
            if (status === GeocodeModel.Ready) {
                navMapRoot.searchPanelVisible = count > 0
            }
        }
    }

    Timer {
        id: searchDebounce
        interval: 350
        repeat: false
        onTriggered: navMapRoot.triggerDestinationSearch()
    }

    /* Invisible container – same size as other menu pages content area */
    Rectangle {
        id: mapArea
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        color: "transparent"
        radius: 16
        clip: true

        Map {
            id: navMap
            anchors.fill: parent
            plugin: darkMapPlugin
            color: "#00091a"
            zoomLevel: 16.8
            tilt: 50
            bearing: NavigationFeed.currentHeadingDeg
            center: navMapRoot.vehicleCoordinate()
            onSupportedMapTypesChanged: navMapRoot.applyPreferredMapType()

            /* Full route shadow — always visible as a dim guide line */
            MapPolyline {
                line.width: 6
                line.color: "#3366aadd"
                path: navMapRoot.routePath
                smooth: true
                opacity: 0.55
            }

            /* Past: already traveled — slightly dimmer */
            MapPolyline {
                line.width: 7
                line.color: "#4488bb"
                path: navMapRoot.pastPath
                smooth: true
                opacity: 0.45
            }

            /* Main segment outer glow */
            MapPolyline {
                line.width: 12
                line.color: "#19395b"
                path: navMapRoot.mainPath
                smooth: true
            }

            /* Main segment — bright cyan route ahead */
            MapPolyline {
                line.width: 7
                line.color: "#7ef2d0"
                path: navMapRoot.mainPath
                smooth: true
            }

            /* Caution segment — yellow approaching turn */
            MapPolyline {
                line.width: 7
                line.color: "#f7df65"
                path: navMapRoot.cautionPath
                smooth: true
            }

            /* Final segment — red near destination */
            MapPolyline {
                line.width: 7
                line.color: "#ff7665"
                path: navMapRoot.finalPath
                smooth: true
            }

            /* Destination pin marker */
            MapQuickItem {
                visible: navMapRoot.destinationCoordinate && navMapRoot.destinationCoordinate.isValid
                coordinate: navMapRoot.destinationCoordinate
                anchorPoint.x: destPin.width / 2
                anchorPoint.y: destPin.height

                sourceItem: Item {
                    id: destPin
                    width: 28
                    height: 36

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            // Pin body
                            ctx.fillStyle = "#ff4444"
                            ctx.beginPath()
                            ctx.arc(14, 12, 12, Math.PI, 0, false)
                            ctx.lineTo(14, 36)
                            ctx.lineTo(2, 12)
                            ctx.closePath()
                            ctx.fill()
                            // Inner circle
                            ctx.fillStyle = "#ffffff"
                            ctx.beginPath()
                            ctx.arc(14, 12, 5, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }
            }

            /* Vehicle position marker */
            MapQuickItem {
                visible: navMapRoot.hasVehicleFix()
                coordinate: navMapRoot.vehicleCoordinate()
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

    Row {
        id: alternativesRow
        anchors.left: mapArea.left
        anchors.leftMargin: 10
        anchors.top: topMiniGuide.bottom
        anchors.topMargin: 8
        spacing: 6
        z: 30
        visible: OsrmRoute.alternativeRoutes.length > 1

        Repeater {
            model: OsrmRoute.alternativeRoutes
            delegate: Rectangle {
                property int routeIdx: index
                property bool selected: OsrmRoute.selectedRouteIndex === routeIdx
                width: 110
                height: 34
                radius: 8
                color: selected ? "#1f4060ee" : "#122131dd"
                border.width: 1
                border.color: selected ? "#6bc7ff" : "#35506c"

                Text {
                    anchors.centerIn: parent
                    color: selected ? "#dff6ff" : "#aac2d8"
                    font.pixelSize: 11
                    text: navMapRoot.formatMeters(modelData.distanceMeters) + " · " +
                          navMapRoot.formatDurationSeconds(modelData.durationSeconds)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        OsrmRoute.selectRoute(routeIdx)
                    }
                }
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

    Rectangle {
        id: destinationSearchCard
        anchors.top: mapArea.top
        anchors.topMargin: 10
        anchors.right: mapArea.right
        anchors.rightMargin: 10
        width: 340
        radius: 12
        color: "#122131dd"
        border.color: "#2a4058"
        border.width: 1
        z: 50

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            TextField {
                id: destinationInput
                width: parent.width
                placeholderText: "Search destination (Mapbox)"
                text: navMapRoot.destinationSearchText
                color: "#e8f2fb"
                placeholderTextColor: "#87a1b8"
                selectByMouse: true
                onTextChanged: {
                    navMapRoot.destinationSearchText = text
                    searchDebounce.restart()
                }
                background: Rectangle {
                    radius: 8
                    color: "#0f1b28"
                    border.color: "#34506c"
                    border.width: 1
                }
            }

            ListView {
                id: geocodeResults
                width: parent.width
                height: navMapRoot.searchPanelVisible ? Math.min(6, destinationGeocode.count) * 42 : 0
                visible: navMapRoot.searchPanelVisible
                clip: true
                spacing: 4
                model: destinationGeocode
                delegate: Rectangle {
                    width: geocodeResults.width
                    height: 38
                    radius: 8
                    color: "#0e1a27"
                    border.color: "#274057"
                    border.width: 1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        elide: Text.ElideRight
                        color: "#d8e9f8"
                        font.pixelSize: 12
                        text: (locationData.address && locationData.address.text)
                              ? locationData.address.text
                              : (locationData.coordinate.latitude.toFixed(5) + ", " + locationData.coordinate.longitude.toFixed(5))
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            navMapRoot.chooseDestinationFromResult(locationData.address, locationData.coordinate)
                        }
                    }
                }
            }
        }
    }
}
