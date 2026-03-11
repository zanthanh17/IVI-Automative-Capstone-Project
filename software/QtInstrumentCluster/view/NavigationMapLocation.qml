import QtQuick 2.12
import QtQuick.Controls 2.12
import QtLocation 5.15
import QtPositioning 5.15
import QtGraphicalEffects 1.12
import NavigationModel 1.0
import NavigationFeed 1.0
import OsrmRoute 1.0

Item {
    id: navMapRoot

    property bool hasMapboxToken: (typeof mapboxTokenFromEnv === "string") && mapboxTokenFromEnv.trim().length > 0

    // Fixed Qt5-compatible style for dashboard navigation.
    property string mapboxStyleUrl: "mapbox://styles/mapbox/navigation-guidance-night-v2"
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

    readonly property real minZoomLevel: 1.0
    readonly property real maxZoomLevel: 19.2
    readonly property real minTilt: 0.0
    readonly property real maxTilt: 60.0
    readonly property real defaultZoomLevel: 14.8
    readonly property real noFixZoomLevel: 2.2
    readonly property real defaultTilt: 0.0
    readonly property real zoomStep: 0.7
    readonly property color mapCardColor: "#132033"
    readonly property int mapCornerRadius: 22
    readonly property int overlayInset: 10
    readonly property int overlayGap: 6
    readonly property int rightControlWidth: 46
    readonly property int rightControlReservedWidth: rightControlWidth + overlayInset + overlayGap
    readonly property int bottomOverlaySafeInset: 36

    property bool followVehicle: true
    property bool autoHeading: false
    property bool overviewMode: false
    property bool centeredOnFirstFix: false

    function clamp(v, minV, maxV) {
        return Math.max(minV, Math.min(maxV, v))
    }

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

    function syncCameraToVehicle(forceCenter) {
        if (!hasVehicleFix()) {
            return
        }
        if (forceCenter || followVehicle) {
            navMap.center = vehicleCoordinate()
        }
        if (autoHeading) {
            navMap.bearing = NavigationFeed.currentHeadingDeg
        }
    }

    function recenterVehicleCamera() {
        followVehicle = true
        autoHeading = true
        overviewMode = false
        navMap.zoomLevel = clamp(defaultZoomLevel, minZoomLevel, maxZoomLevel)
        navMap.tilt = clamp(defaultTilt, minTilt, maxTilt)
        syncCameraToVehicle(true)
    }

    function showRouteOverview() {
        if (routePath.length < 2 && !(destinationCoordinate && destinationCoordinate.isValid)) {
            return
        }
        overviewMode = true
        followVehicle = false
        autoHeading = false
        navMap.bearing = 0
        navMap.tilt = 25
        if (typeof navMap.fitViewportToMapItems === "function") {
            navMap.fitViewportToMapItems()
        }
        navMap.zoomLevel = clamp(navMap.zoomLevel, minZoomLevel, maxZoomLevel)
    }

    function zoomBy(delta) {
        overviewMode = false
        followVehicle = false
        navMap.zoomLevel = clamp(navMap.zoomLevel + delta, minZoomLevel, maxZoomLevel)
    }

    function applyPreferredMapType() {
        if (!navMap.supportedMapTypes || navMap.supportedMapTypes.length === 0) {
            return
        }

        // The additional_style_urls style is registered as MapType.CustomMap.
        // Prefer it if available (must be a classic style — NOT Standard/imports).
        for (var i = 0; i < navMap.supportedMapTypes.length; ++i) {
            var mt = navMap.supportedMapTypes[i]
            if (mt.style === MapType.CustomMap) {
                navMap.activeMapType = mt
                console.log("[NavMap] Selected custom map style:", mt.name || "(custom)")
                return
            }
        }

        // Fallback: any dark / navigation style
        for (var j = 0; j < navMap.supportedMapTypes.length; ++j) {
            var fb = navMap.supportedMapTypes[j]
            var text = ((fb.name || "") + " " + (fb.description || "")).toLowerCase()
            if (text.indexOf("dark") >= 0 || text.indexOf("navigation") >= 0 || text.indexOf("night") >= 0) {
                navMap.activeMapType = fb
                console.log("[NavMap] Selected fallback map style:", fb.name || fb.description)
                return
            }
        }

        if (navMap.supportedMapTypes.length > 0) {
            navMap.activeMapType = navMap.supportedMapTypes[0]
            console.log("[NavMap] Selected first available map style:", navMap.activeMapType.name || navMap.activeMapType.description)
        }
    }

    function logSupportedMapTypes() {
        if (!navMap.supportedMapTypes || navMap.supportedMapTypes.length === 0) {
            console.warn("[NavMap] No supported map types reported by mapboxgl plugin.")
            return
        }
        var lines = []
        for (var i = 0; i < navMap.supportedMapTypes.length; ++i) {
            var mt = navMap.supportedMapTypes[i]
            lines.push("#" + i + " style=" + mt.style + " name=\"" + (mt.name || "")
                       + "\" desc=\"" + (mt.description || "") + "\"")
        }
        console.log("[NavMap] Supported map types:", lines.join(" | "))
    }

    Component.onCompleted: {
        if (!hasMapboxToken) {
            console.warn("[NavMap] MAPBOX_ACCESS_TOKEN is empty. Mapbox tiles/geocode/route requests will fail.")
        }
        console.log("[NavMap] Using map style URL:", mapboxStyleUrl)
        logSupportedMapTypes()
        rebuildRouteFromActiveSource()
        applyPreferredMapType()
        requestRouteToDestination()
        syncCameraToVehicle(true)
        if (!hasVehicleFix()) {
            console.log("[NavMap] No GPS fix yet. Map keeps provider default center until first valid position.")
        }
        console.log("[NavMap] Route initialized with", routePath.length, "points")
    }

    Timer {
        id: osrmRetryTimer
        interval: 3000
        repeat: false
        onTriggered: {
            console.log("[NavMap] Retrying route request (attempt", navMapRoot.osrmRetryCount + 1, ")")
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
            if (!navMapRoot.centeredOnFirstFix && navMapRoot.hasVehicleFix()) {
                navMap.zoomLevel = navMapRoot.clamp(navMapRoot.defaultZoomLevel,
                                                    navMapRoot.minZoomLevel,
                                                    navMapRoot.maxZoomLevel)
                navMapRoot.syncCameraToVehicle(true)
                navMapRoot.centeredOnFirstFix = true
            }
            if (!navMapRoot.liveRouteReady) {
                navMapRoot.requestRouteToDestination()
            } else {
                navMapRoot.maybeRerouteIfOffRoute()
            }
            navMapRoot.syncCameraToVehicle(false)
        }
        function onRouteLooped() {
            console.log("[NavMap] Route looped, rebuilding path")
            navMapRoot.rebuildRouteFromActiveSource()
            if (navMapRoot.overviewMode) {
                navMapRoot.showRouteOverview()
            }
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
            console.log("[NavMap] Route received with", path.length, "points")
            navMapRoot.osrmRetryCount = 0
            navMapRoot.liveRouteReady = true
            navMapRoot.rebuildRouteFromActiveSource()
            if (navMapRoot.overviewMode) {
                navMapRoot.showRouteOverview()
            }
        }
        function onRouteFailed(error) {
            console.warn("[NavMap] Route request failed:", error)
            navMapRoot.liveRouteReady = false
            navMapRoot.rebuildRouteFromActiveSource()
            if (navMapRoot.osrmRetryCount < navMapRoot.osrmMaxRetries) {
                navMapRoot.osrmRetryCount++
                osrmRetryTimer.restart()
            }
        }
    }

    /*
     * Mapbox GL native plugin — requires access token.
     * Uses a single style URL from env (MAPBOX_STYLE_URL).
     */
    // Token is injected from main.cpp via QML context property: mapboxTokenFromEnv
    // Set before running: export MAPBOX_ACCESS_TOKEN="pk.eyJ1..."

    Plugin {
        id: darkMapPlugin
        name: "mapboxgl"
        PluginParameter { name: "mapboxgl.access_token"; value: mapboxTokenFromEnv }
        PluginParameter {
            name: "mapboxgl.mapping.additional_style_urls"
            value: mapboxStyleUrl
        }
    }

    Plugin {
        id: geocodePlugin
        name: "mapbox"
        PluginParameter { name: "mapbox.access_token"; value: mapboxTokenFromEnv }
    }

    GeocodeModel {
        id: destinationGeocode
        plugin: geocodePlugin
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
        anchors.margins: 0
        color: "transparent"
        radius: navMapRoot.mapCornerRadius

        /*
         * Use layer + OpacityMask for true rounded-corner clipping.
         * This works even for native OpenGL content like QtLocation Map.
         */
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: mapArea.width
                height: mapArea.height
                radius: navMapRoot.mapCornerRadius
            }
        }

        // Dark base fill behind the map
        Rectangle {
            anchors.fill: parent
            color: navMapRoot.mapCardColor
            radius: navMapRoot.mapCornerRadius
        }

        Map {
            id: navMap
            anchors.fill: parent
            plugin: darkMapPlugin
            color: "#00091a"
            minimumZoomLevel: navMapRoot.minZoomLevel
            maximumZoomLevel: navMapRoot.maxZoomLevel
            zoomLevel: navMapRoot.defaultZoomLevel
            tilt: navMapRoot.defaultTilt
            bearing: 0
            onSupportedMapTypesChanged: {
                navMapRoot.logSupportedMapTypes()
                navMapRoot.applyPreferredMapType()
            }
            onErrorChanged: {
                if (error !== Map.NoError) {
                    console.warn("[NavMap] Map render error:", error, errorString)
                }
            }
            Component.onCompleted: {
                console.log("[NavMap] Map component created. Active type:",
                            activeMapType ? activeMapType.name : "(none)")
                if (!navMapRoot.hasVehicleFix()) {
                    zoomLevel = navMapRoot.clamp(navMapRoot.noFixZoomLevel,
                                                 navMapRoot.minZoomLevel,
                                                 navMapRoot.maxZoomLevel)
                }
            }

            gesture.enabled: true
            gesture.acceptedGestures: MapGestureArea.PanGesture
                                      | MapGestureArea.PinchGesture
                                      | MapGestureArea.RotationGesture
                                      | MapGestureArea.FlickGesture
            gesture.onPanStarted: {
                navMapRoot.followVehicle = false
                navMapRoot.overviewMode = false
            }
            gesture.onPinchStarted: {
                navMapRoot.followVehicle = false
                navMapRoot.overviewMode = false
            }

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

    /* Border frame drawn on top of the clipped map */
    Rectangle {
        id: mapBorderFrame
        anchors.fill: mapArea
        z: 22
        color: "transparent"
        radius: navMapRoot.mapCornerRadius
        border.width: 1.5
        border.color: "#3a5270"
    }

    /* ── Right-side column: search card + zoom + action buttons ── */
    Column {
        id: rightControlColumn
        anchors.top: mapArea.top
        anchors.topMargin: navMapRoot.overlayInset
        anchors.right: mapArea.right
        anchors.rightMargin: navMapRoot.overlayInset
        width: navMapRoot.rightControlWidth
        spacing: navMapRoot.overlayGap
        z: 50

        // Zoom in / out control
        Rectangle {
            id: zoomControl
            width: parent.width
            height: 80
            radius: 10
            color: "#1e2a3add"
            border.width: 1
            border.color: "#415568"

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 - 1
                width: parent.width - 12
                height: 1
                color: "#415568"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                color: "#f3f6ff"
                font.pixelSize: 20
                font.bold: true
                text: "+"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 + 8
                color: "#f3f6ff"
                font.pixelSize: 24
                text: "−"
            }

            MouseArea {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height / 2
                onClicked: navMapRoot.zoomBy(navMapRoot.zoomStep)
            }
            MouseArea {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height / 2
                onClicked: navMapRoot.zoomBy(-navMapRoot.zoomStep)
            }
        }

        // Compass / heading button
        Rectangle {
            width: parent.width
            height: parent.width
            radius: 10
            color: navMapRoot.autoHeading ? "#1d4f87ee" : "#1e2a3add"
            border.width: 1
            border.color: navMapRoot.autoHeading ? "#7fb8f6" : "#415568"

            Canvas {
                anchors.centerIn: parent
                width: 18
                height: 18
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = "#f3f6ff"
                    ctx.fillStyle = "#f3f6ff"
                    ctx.lineWidth = 1.6
                    ctx.beginPath()
                    ctx.arc(9, 9, 7, 0, Math.PI * 2)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(9, 2.5)
                    ctx.lineTo(11.5, 9.5)
                    ctx.lineTo(9, 8.2)
                    ctx.lineTo(6.5, 9.5)
                    ctx.closePath()
                    ctx.fill()
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    navMapRoot.autoHeading = !navMapRoot.autoHeading
                    navMapRoot.overviewMode = false
                    if (navMapRoot.autoHeading) {
                        navMapRoot.followVehicle = true
                        navMapRoot.syncCameraToVehicle(true)
                    } else {
                        navMap.bearing = 0
                    }
                }
            }
        }

        // Follow vehicle button
        Rectangle {
            width: parent.width
            height: parent.width
            radius: 10
            color: navMapRoot.followVehicle ? "#1d4f87ee" : "#1e2a3add"
            border.width: 1
            border.color: navMapRoot.followVehicle ? "#7fb8f6" : "#415568"

            Canvas {
                anchors.centerIn: parent
                width: 18
                height: 18
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = "#f3f6ff"
                    ctx.beginPath()
                    ctx.moveTo(9, 1.5)
                    ctx.lineTo(16, 16)
                    ctx.lineTo(9, 12)
                    ctx.lineTo(2, 16)
                    ctx.closePath()
                    ctx.fill()
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    navMapRoot.followVehicle = !navMapRoot.followVehicle
                    navMapRoot.overviewMode = false
                    if (navMapRoot.followVehicle) {
                        navMapRoot.syncCameraToVehicle(true)
                    }
                }
            }
        }

        // Overview / recenter button
        Rectangle {
            width: parent.width
            height: parent.width
            radius: 10
            color: navMapRoot.overviewMode ? "#1d4f87ee" : "#1e2a3add"
            border.width: 1
            border.color: navMapRoot.overviewMode ? "#7fb8f6" : "#415568"

            Canvas {
                anchors.centerIn: parent
                width: 18
                height: 18
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = "#f3f6ff"
                    ctx.lineWidth = 1.6
                    ctx.beginPath()
                    ctx.arc(9, 9, 5, 0, Math.PI * 2)
                    ctx.moveTo(9, 0.8)
                    ctx.lineTo(9, 3.5)
                    ctx.moveTo(9, 14.5)
                    ctx.lineTo(9, 17.2)
                    ctx.moveTo(0.8, 9)
                    ctx.lineTo(3.5, 9)
                    ctx.moveTo(14.5, 9)
                    ctx.lineTo(17.2, 9)
                    ctx.stroke()
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: navMapRoot.recenterVehicleCamera()
                onPressAndHold: navMapRoot.showRouteOverview()
            }
        }
    }

    /* ── Search card (top, left of right controls) ── */
    Rectangle {
        id: destinationSearchCard
        anchors.top: mapArea.top
        anchors.topMargin: navMapRoot.overlayInset
        anchors.left: mapArea.left
        anchors.leftMargin: navMapRoot.overlayInset
        anchors.right: rightControlColumn.left
        anchors.rightMargin: navMapRoot.overlayGap
        radius: 10
        color: "#0f1d2dee"
        border.color: "#2e4a62"
        border.width: 1
        z: 50

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            TextField {
                id: destinationInput
                width: parent.width
                height: 34
                placeholderText: "Search destination"
                text: navMapRoot.destinationSearchText
                color: "#e8f2fb"
                placeholderTextColor: "#87a1b8"
                selectByMouse: true
                font.pixelSize: 12
                leftPadding: 10
                onTextChanged: {
                    navMapRoot.destinationSearchText = text
                    searchDebounce.restart()
                }
                background: Rectangle {
                    radius: 7
                    color: "#0a1520"
                    border.color: "#2e4a62"
                    border.width: 1
                }
            }

            ListView {
                id: geocodeResults
                width: parent.width
                height: navMapRoot.searchPanelVisible ? Math.min(6, destinationGeocode.count) * 40 : 0
                visible: navMapRoot.searchPanelVisible
                clip: true
                spacing: 3
                model: destinationGeocode
                delegate: Rectangle {
                    width: geocodeResults.width
                    height: 36
                    radius: 7
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
                        font.pixelSize: 11
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

    /* ── Top mini-guide (turn cue) — below search card ── */
    Rectangle {
        id: topMiniGuide
        anchors.left: mapArea.left
        anchors.leftMargin: navMapRoot.overlayInset
        anchors.right: rightControlColumn.left
        anchors.rightMargin: navMapRoot.overlayGap
        anchors.top: destinationSearchCard.bottom
        anchors.topMargin: navMapRoot.overlayGap
        height: 40
        radius: 10
        color: "#0f1d2dee"
        border.width: 1
        border.color: "#2a4058"
        z: 44

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 6
            anchors.bottomMargin: 6
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
                    font.pixelSize: 14
                    font.bold: true
                }
                Text {
                    text: navMapRoot.maneuverVerb(NavigationModel.maneuver)
                    color: "#99b4cf"
                    font.pixelSize: 10
                }
            }
        }
    }

    Row {
        id: alternativesRow
        anchors.left: mapArea.left
        anchors.leftMargin: navMapRoot.overlayInset
        anchors.right: rightControlColumn.left
        anchors.rightMargin: navMapRoot.overlayGap
        anchors.top: topMiniGuide.bottom
        anchors.topMargin: navMapRoot.overlayGap
        clip: true
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

    Rectangle {
        id: tokenWarningCard
        anchors.top: destinationSearchCard.bottom
        anchors.topMargin: navMapRoot.overlayGap
        anchors.left: mapArea.left
        anchors.leftMargin: navMapRoot.overlayInset
        visible: !navMapRoot.hasMapboxToken
        width: tokenWarningText.implicitWidth + 16
        height: tokenWarningText.implicitHeight + 12
        radius: 8
        color: "#4a1f2acc"
        border.color: "#d86f88"
        border.width: 1
        z: 40

        Text {
            id: tokenWarningText
            anchors.margins: 8
            anchors.fill: parent
            color: "#ffdbe5"
            font.pixelSize: 11
            text: "MAPBOX_ACCESS_TOKEN missing. Mapbox services are unavailable."
        }
    }

    /* ── Guide panel (bottom) ── */
    Rectangle {
        id: guidePanel
        anchors.left: mapArea.left
        anchors.right: mapArea.right
        anchors.bottom: mapArea.bottom
        anchors.leftMargin: navMapRoot.overlayInset
        anchors.rightMargin: navMapRoot.rightControlReservedWidth
        anchors.bottomMargin: navMapRoot.overlayInset
        height: 68
        radius: 10
        color: "#0f1d2dee"
        border.width: 1
        border.color: "#2a4058"
        z: 36

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Row {
                spacing: 8

                Canvas {
                    width: 24
                    height: 24
                    onPaint: navMapRoot.drawArrow(getContext("2d"), NavigationModel.maneuver, "#7ef2d0")
                }

                Text {
                    width: guidePanel.width - 170
                    elide: Text.ElideRight
                    text: NavigationModel.nextStreet.length > 0 ? NavigationModel.nextStreet : NavigationModel.currentStreet
                    color: "#f0f8ff"
                    font.pixelSize: 16
                    font.bold: true
                }

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
}
