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
    property bool enableVietnameseTelex: true
    property bool biasSearchToCurrentCity: true
    property string preferredSearchCity: "Da Nang"
    property string preferredSearchCityLocal: "Đà Nẵng"
    property string preferredSearchCountry: "Vietnam"
    property real preferredSearchLat: 16.061911
    property real preferredSearchLon: 108.219773
    property bool liveRouteReady: false
    property bool navigationActive: false
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

    function hasAnyVietnameseMark(word) {
        return /[ăâêôơưđáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]/i.test(word)
    }

    function applyBaseTelex(word) {
        var out = word
        out = out.replace(/([dD])[dD]/g, function(_, d) { return d === "D" ? "Đ" : "đ" })
        out = out.replace(/([aA])[aA]/g, function(_, a) { return a === "A" ? "Â" : "â" })
        out = out.replace(/([aA])[wW]/g, function(_, a) { return a === "A" ? "Ă" : "ă" })
        out = out.replace(/([eE])[eE]/g, function(_, e) { return e === "E" ? "Ê" : "ê" })
        out = out.replace(/([oO])[oO]/g, function(_, o) { return o === "O" ? "Ô" : "ô" })
        out = out.replace(/([oO])[wW]/g, function(_, o) { return o === "O" ? "Ơ" : "ơ" })
        out = out.replace(/([uU])[wW]/g, function(_, u) { return u === "U" ? "Ư" : "ư" })
        return out
    }

    function toneIndexFromKey(toneKey) {
        var k = toneKey.toLowerCase()
        if (k === "s") return 1
        if (k === "f") return 2
        if (k === "r") return 3
        if (k === "x") return 4
        if (k === "j") return 5
        return 0
    }

    function vowelToneForms(ch) {
        var forms = {
            "a": "aáàảãạ", "ă": "ăắằẳẵặ", "â": "âấầẩẫậ",
            "e": "eéèẻẽẹ", "ê": "êếềểễệ",
            "i": "iíìỉĩị",
            "o": "oóòỏõọ", "ô": "ôốồổỗộ", "ơ": "ơớờởỡợ",
            "u": "uúùủũụ", "ư": "ưứừửữự",
            "y": "yýỳỷỹỵ",
            "A": "AÁÀẢÃẠ", "Ă": "ĂẮẰẲẴẶ", "Â": "ÂẤẦẨẪẬ",
            "E": "EÉÈẺẼẸ", "Ê": "ÊẾỀỂỄỆ",
            "I": "IÍÌỈĨỊ",
            "O": "OÓÒỎÕỌ", "Ô": "ÔỐỒỔỖỘ", "Ơ": "ƠỚỜỞỠỢ",
            "U": "UÚÙỦŨỤ", "Ư": "ƯỨỪỬỮỰ",
            "Y": "YÝỲỶỸỴ"
        }
        return forms[ch] || ""
    }

    function isVowelWithToneSupport(ch) {
        return vowelToneForms(ch).length === 6
    }

    function chooseVietnameseTonePosition(word, vowelPositions) {
        if (vowelPositions.length === 0) {
            return -1
        }
        if (vowelPositions.length === 1) {
            return vowelPositions[0]
        }
        if (vowelPositions.length >= 3) {
            return vowelPositions[1]
        }

        var i0 = vowelPositions[0]
        var i1 = vowelPositions[1]
        var c0 = word.charAt(i0).toLowerCase()
        var c1 = word.charAt(i1).toLowerCase()
        var endsWithSecondVowel = (i1 === word.length - 1)

        if (endsWithSecondVowel) {
            if ((c0 === "o" && (c1 === "a" || c1 === "e")) || (c0 === "u" && c1 === "y")) {
                return i0
            }
            if (c0 === "u" && c1 === "e") {
                return i1
            }
            return i0
        }

        return i1
    }

    function applyToneToVietnameseWord(word, toneKey) {
        var toneIdx = toneIndexFromKey(toneKey)
        if (toneIdx <= 0) {
            return word
        }

        var vowelPositions = []
        for (var i = 0; i < word.length; ++i) {
            if (isVowelWithToneSupport(word.charAt(i))) {
                vowelPositions.push(i)
            }
        }

        var tonePos = chooseVietnameseTonePosition(word, vowelPositions)
        if (tonePos < 0) {
            return word
        }

        var target = word.charAt(tonePos)
        var forms = vowelToneForms(target)
        if (forms.length !== 6) {
            return word
        }

        var toned = forms.charAt(toneIdx)
        return word.slice(0, tonePos) + toned + word.slice(tonePos + 1)
    }

    function looksLikeVietnameseSyllable(word) {
        if (hasAnyVietnameseMark(word)) {
            return true
        }
        if (/(dd|[aeo]w|aa|ee|oo|uw)/i.test(word)) {
            return true
        }
        if (/(qu|gi|ng|nh|th|tr|ph|kh|ch)/i.test(word)) {
            return true
        }
        return /[aeiouy]{2,}/i.test(word)
    }

    function convertTelexWord(word) {
        if (!enableVietnameseTelex || word.length < 2) {
            return word
        }

        var original = word
        var base = applyBaseTelex(word)
        var toneKey = ""
        var body = base

        if (/[sfrxjSFRXJ]$/.test(base)) {
            toneKey = base.charAt(base.length - 1)
            body = base.slice(0, -1)
        } else if (/[tT][tT]$/.test(base) && hasAnyVietnameseMark(base)) {
            // Convenience fallback for users typing "...tt" expecting "nặng".
            toneKey = "j"
            body = base.slice(0, -1)
        }

        if (toneKey.length === 0) {
            return base
        }

        if (!looksLikeVietnameseSyllable(original) && !looksLikeVietnameseSyllable(body)) {
            return original
        }

        return applyToneToVietnameseWord(body, toneKey)
    }

    function normalizeVietnameseTelexInput(rawText) {
        if (!enableVietnameseTelex || rawText.length === 0) {
            return rawText
        }

        var m = rawText.match(/([A-Za-zĐđĂăÂâÊêÔôƠơƯư]+)$/)
        if (!m || m.length < 2) {
            return rawText
        }

        var tailWord = m[1]
        var converted = convertTelexWord(tailWord)
        if (converted === tailWord) {
            return rawText
        }
        return rawText.slice(0, rawText.length - tailWord.length) + converted
    }

    function effectiveSearchCenter() {
        var c = vehicleCoordinate()
        if (c && c.isValid) {
            return c
        }
        return QtPositioning.coordinate(preferredSearchLat, preferredSearchLon)
    }

    function containsPreferredCity(textLower) {
        return textLower.indexOf("da nang") >= 0
               || textLower.indexOf("danang") >= 0
               || textLower.indexOf("đà nẵng") >= 0
    }

    function buildCityBiasedQuery(rawQuery) {
        var q = rawQuery.trim()
        if (!biasSearchToCurrentCity || q.length === 0) {
            return q
        }

        var lower = q.toLowerCase()
        if (containsPreferredCity(lower)
                || lower.indexOf("vietnam") >= 0
                || lower.indexOf("việt nam") >= 0) {
            return q
        }

        return q + ", " + preferredSearchCityLocal + ", " + preferredSearchCountry
    }

    function triggerDestinationSearch() {
        var q = destinationSearchText.trim()
        if (q.length < 3) {
            searchPanelVisible = false
            return
        }
        destinationGeocode.query = buildCityBiasedQuery(q)
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
        navigationActive = false
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

    function getManeuverIcon(value) {
        if (value === NavigationModel.TurnLeft) return "qrc:/images/map/turn_left.svg"
        if (value === NavigationModel.TurnRight) return "qrc:/images/map/turn_right.svg"
        if (value === NavigationModel.GoStraight) return "qrc:/images/map/go_straight.svg"
        if (value === NavigationModel.UTurn) return "qrc:/images/map/u_turn.svg"
        if (value === NavigationModel.Arrive) return "qrc:/images/map/arrive.svg"
        return "qrc:/images/map/go_straight.svg"
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
            
            // Only rebuild visual path line; don't start feeding driving data yet
            navMapRoot.rebuildRouteFromActiveSource()
            if (navMapRoot.overviewMode) {
                navMapRoot.showRouteOverview()
            }
        }
        function onRouteStepsChanged() {
            // Can sync if necessary, but we choose to only push data to NavigationModel upon "Start"
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
        PluginParameter {
            name: "mapbox.geocoding.proximity"
            value: {
                var c = navMapRoot.effectiveSearchCenter()
                return c.longitude + "," + c.latitude
            }
        }
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

        // Glassmorphic background for grouped controls (zoom in/out)
        Rectangle {
            width: parent.width
            height: 96
            radius: 20
            color: "#661A202C" // Glassmorphic dark
            border.width: 1
            border.color: "#33FFFFFF"
            
            // Blur effect simulation via background manipulation is complex in QML without specific QtGraphicalEffects or Qt 6 MultiEffect.
            // Using translucent color for a glassmorphic look.

            Column {
                anchors.fill: parent
                // Zoom In
                Item {
                    width: parent.width
                    height: 48
                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: "qrc:/images/map/zoom_in.svg"
                        sourceSize: Qt.size(24, 24)
                        opacity: zoomInMouse.pressed ? 0.6 : 1.0
                    }
                    MouseArea {
                        id: zoomInMouse
                        anchors.fill: parent
                        onClicked: navMapRoot.zoomBy(navMapRoot.zoomStep)
                    }
                }
                Rectangle { // Divider
                    width: parent.width - 16
                    height: 1
                    color: "#33FFFFFF"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                // Zoom Out
                Item {
                    width: parent.width
                    height: 47
                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: "qrc:/images/map/zoom_out.svg"
                        sourceSize: Qt.size(24, 24)
                        opacity: zoomOutMouse.pressed ? 0.6 : 1.0
                    }
                    MouseArea {
                        id: zoomOutMouse
                        anchors.fill: parent
                        onClicked: navMapRoot.zoomBy(-navMapRoot.zoomStep)
                    }
                }
            }
        }

        // Compass / heading button
        Rectangle {
            width: parent.width
            height: parent.width
            radius: 20
            color: navMapRoot.autoHeading ? "#992D5BF5" : "#661A202C"
            border.width: 1
            border.color: navMapRoot.autoHeading ? "#2D5BF5" : "#33FFFFFF"

            Image {
                anchors.centerIn: parent
                width: 24
                height: 24
                source: "qrc:/images/map/compass.svg"
                sourceSize: Qt.size(24, 24)
                opacity: compassMouse.pressed ? 0.6 : 1.0
                rotation: navMapRoot.autoHeading ? 0 : -navMap.bearing
                Behavior on rotation { NumberAnimation { duration: 200 } }
            }
            MouseArea {
                id: compassMouse
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
            radius: 20
            color: navMapRoot.followVehicle ? "#992D5BF5" : "#661A202C"
            border.width: 1
            border.color: navMapRoot.followVehicle ? "#2D5BF5" : "#33FFFFFF"

            Image {
                anchors.centerIn: parent
                width: 24
                height: 24
                source: "qrc:/images/map/follow.svg"
                sourceSize: Qt.size(24, 24)
                opacity: followMouse.pressed ? 0.6 : 1.0
            }
            MouseArea {
                id: followMouse
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
            radius: 20
            color: navMapRoot.overviewMode ? "#992D5BF5" : "#661A202C"
            border.width: 1
            border.color: navMapRoot.overviewMode ? "#2D5BF5" : "#33FFFFFF"

            Image {
                anchors.centerIn: parent
                width: 24
                height: 24
                source: "qrc:/images/map/overview.svg"
                sourceSize: Qt.size(24, 24)
                opacity: recenterMouse.pressed ? 0.6 : 1.0
            }
            MouseArea {
                id: recenterMouse
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
        radius: 20
        color: "#661A202C"
        border.color: "#33FFFFFF"
        border.width: 1
        z: 50
        height: Math.max(40, destinationInput.height + (navMapRoot.searchPanelVisible ? Math.min(6, destinationGeocode.count) * 40 + 8 : 8))

        Column {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            Row {
                width: parent.width
                height: 32
                spacing: 8
                
                Item {
                    width: 32
                    height: 32
                    Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: "qrc:/images/map/search.svg"
                        sourceSize: Qt.size(20, 20)
                        opacity: 0.8
                    }
                }

                TextField {
                    id: destinationInput
                    width: parent.width - 40
                    height: 32
                    placeholderText: "Search destination (Da Nang)"
                    text: navMapRoot.destinationSearchText
                    color: "#FFFFFF"
                    placeholderTextColor: "#88FFFFFF"
                    selectByMouse: true
                    font.pixelSize: 13
                    leftPadding: 2
                    background: Item {} // Remove background to blend into glassmorphic card
                    onTextEdited: {
                        var normalized = navMapRoot.normalizeVietnameseTelexInput(text)
                        if (normalized !== text) {
                            var oldCursor = cursorPosition
                            text = normalized
                            cursorPosition = Math.min(text.length, oldCursor)
                        }
                        navMapRoot.destinationSearchText = text
                        searchDebounce.restart()
                    }
                }
            }

            ListView {
                id: geocodeResults
                width: parent.width - 8
                anchors.horizontalCenter: parent.horizontalCenter
                height: navMapRoot.searchPanelVisible ? Math.min(6, destinationGeocode.count) * 40 : 0
                visible: navMapRoot.searchPanelVisible
                clip: true
                spacing: 2
                model: destinationGeocode
                delegate: Rectangle {
                    width: geocodeResults.width
                    height: 38
                    radius: 12
                    color: itemMouseArea.pressed ? "#44FFFFFF" : (itemMouseArea.containsMouse ? "#22FFFFFF" : "transparent")
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        elide: Text.ElideRight
                        color: "#FFFFFF"
                        font.pixelSize: 12
                        text: (locationData.address && locationData.address.text)
                                ? locationData.address.text
                                : (locationData.coordinate.latitude.toFixed(5) + ", " + locationData.coordinate.longitude.toFixed(5))
                    }

                    MouseArea {
                        id: itemMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            navMapRoot.chooseDestinationFromResult(locationData.address, locationData.coordinate)
                        }
                    }
                }
            }
        }
    }

    /* ── Top guide (consolidated turn cue) ── */
    Rectangle {
        id: topMiniGuide
        visible: navMapRoot.navigationActive
        anchors.left: mapArea.left
        anchors.leftMargin: navMapRoot.overlayInset
        anchors.right: rightControlColumn.left
        anchors.rightMargin: navMapRoot.overlayGap
        anchors.top: destinationSearchCard.bottom
        anchors.topMargin: navMapRoot.overlayGap
        height: (NavigationModel.currentStep + 1 < NavigationModel.route.length) ? 96 : 72
        radius: 20
        color: "#D9161B22" // Deeper, modern dark theme base
        border.width: 1
        border.color: "#4DFFFFFF"
        z: 44

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Row {
                width: parent.width
                spacing: 16
                
                Image {
                    width: 44
                    height: 44
                    anchors.verticalCenter: parent.verticalCenter
                    source: navMapRoot.getManeuverIcon(NavigationModel.maneuver)
                    sourceSize: Qt.size(44, 44)
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 60
                    spacing: 2

                    Row {
                        width: parent.width
                        spacing: 8
                        clip: true
                        
                        Text {
                            id: distText
                            text: NavigationModel.distanceToTurnText
                            color: "#FFFFFF"
                            font.pixelSize: 22
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: NavigationModel.nextStreet.length > 0 ? NavigationModel.nextStreet : NavigationModel.currentStreet
                            color: "#E2E8F0"
                            font.pixelSize: 18
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width - distText.width - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: navMapRoot.maneuverVerb(NavigationModel.maneuver)
                        color: "#94A3B8"
                        font.pixelSize: 13
                        font.bold: true
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#1AFFFFFF"
                visible: NavigationModel.currentStep + 1 < NavigationModel.route.length
            }

            Row {
                spacing: 8
                visible: NavigationModel.currentStep + 1 < NavigationModel.route.length
                anchors.left: parent.left
                anchors.leftMargin: 8

                Text {
                    text: "THEN"
                    color: "#64748B"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 0.5
                    anchors.verticalCenter: parent.verticalCenter
                }

                Image {
                    width: 18
                    height: 18
                    property int nextManeuver: (NavigationModel.currentStep + 1 < NavigationModel.route.length)
                                               ? NavigationModel.route[NavigationModel.currentStep + 1].maneuver
                                               : NavigationModel.Arrive
                    source: navMapRoot.getManeuverIcon(nextManeuver)
                    sourceSize: Qt.size(18, 18)
                    opacity: 0.8
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    property string nextStreet: (NavigationModel.currentStep + 1 < NavigationModel.route.length)
                                                ? NavigationModel.route[NavigationModel.currentStep + 1].next
                                                : "Destination"
                    text: nextStreet
                    color: "#CBD5E1"
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, topMiniGuide.width - 160)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    property real nextDistance: (NavigationModel.currentStep + 1 < NavigationModel.route.length)
                                                ? NavigationModel.route[NavigationModel.currentStep + 1].dist
                                                : 0
                    text: nextDistance > 0 ? ("in " + navMapRoot.formatMeters(nextDistance)) : ""
                    color: "#38BDF8"
                    font.pixelSize: 12
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
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
        anchors.top: navMapRoot.navigationActive ? topMiniGuide.bottom : destinationSearchCard.bottom
        anchors.topMargin: navMapRoot.overlayGap
        clip: true
        spacing: 6
        z: 30
        visible: OsrmRoute.alternativeRoutes.length > 1 && !navMapRoot.navigationActive

        Repeater {
            model: OsrmRoute.alternativeRoutes
            delegate: Rectangle {
                property int routeIdx: index
                property bool selected: OsrmRoute.selectedRouteIndex === routeIdx
                width: 110
                height: 34
                radius: 17 // more rounded
                color: selected ? "#4C2D5BF5" : "#661A202C"
                border.width: 1
                border.color: selected ? "#6bc7ff" : "#33FFFFFF"

                Text {
                    anchors.centerIn: parent
                    color: selected ? "#FFFFFF" : "#A0AEC0"
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

    /* ── Start Navigation Button ── */
    Rectangle {
        id: startNavButton
        anchors.left: mapArea.left
        anchors.leftMargin: navMapRoot.overlayInset
        anchors.top: alternativesRow.visible ? alternativesRow.bottom : destinationSearchCard.bottom
        anchors.topMargin: navMapRoot.overlayGap
        width: 140
        height: 48
        radius: 24
        color: startArea.pressed ? "#1C3FAF" : "#2D5BF5"
        visible: navMapRoot.liveRouteReady && !navMapRoot.navigationActive
        z: 40
        border.width: 1
        border.color: "#4DFFFFFF"

        Row {
            anchors.centerIn: parent
            spacing: 8
            
            Image {
                width: 20
                height: 20
                source: "qrc:/images/map/go_straight.svg"
                sourceSize: Qt.size(20, 20)
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Start"
                color: "#FFFFFF"
                font.pixelSize: 18
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: startArea
            anchors.fill: parent
            onClicked: {
                navMapRoot.navigationActive = true
                navMapRoot.followVehicle = true
                navMapRoot.autoHeading = true
                
                // 2. Inject parsed map steps into the instruction model
                NavigationModel.setRouteSteps(OsrmRoute.routeSteps)
                
                // 3. Transform map perspective
                navMapRoot.overviewMode = false
                navMap.zoomLevel = 18.0
                navMap.tilt = 60.0
                navMapRoot.syncCameraToVehicle(true)
            }
        }
    }



}
