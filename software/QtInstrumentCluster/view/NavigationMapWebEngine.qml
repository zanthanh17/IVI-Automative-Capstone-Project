import QtQuick 2.12
import QtWebEngine
import NavigationModel 1.0
import NavigationFeed 1.0
import OsrmRoute 1.0

Item {
    id: navWebRoot

    property var routeLngLat: []
    property var mockRouteLngLat: []
    property bool pageReady: false
    property bool liveRouteReady: false
    property var destination: { "lat": 16.05200, "lon": 108.21870 }
    property int osrmRetryCount: 0
    readonly property int osrmMaxRetries: 2

    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function buildMockRouteLngLat() {
        var list = []
        var raw = NavigationFeed.mockRoute
        for (var i = 0; i < raw.length; ++i) {
            list.push([raw[i].lon, raw[i].lat])
        }
        return list
    }

    function geoVariantToLngLatArray(geoPath) {
        var out = []
        if (!geoPath) {
            return out
        }
        for (var i = 0; i < geoPath.length; ++i) {
            var c = geoPath[i]
            if (c && c.latitude !== undefined && c.longitude !== undefined) {
                out.push([c.longitude, c.latitude])
            }
        }
        return out
    }

    function currentRoute() {
        if (liveRouteReady && routeLngLat.length > 1) {
            return routeLngLat
        }
        return mockRouteLngLat
    }

    function runJsCall(functionName, payload) {
        if (!pageReady) {
            return
        }
        var arg = JSON.stringify(payload)
        mapWebView.runJavaScript("window." + functionName + "(" + arg + ");")
    }

    function pushRoute() {
        runJsCall("setRoute", {
                      coordinates: currentRoute(),
                      progress: clamp01(NavigationModel.routeProgress)
                  })
    }

    function pushVehicle() {
        runJsCall("setVehicleState", {
                      lat: NavigationFeed.currentLatitude,
                      lng: NavigationFeed.currentLongitude,
                      heading: NavigationFeed.currentHeadingDeg,
                      speedKmh: NavigationFeed.currentSpeedKmh
                  })
    }

    function pushProgress() {
        runJsCall("setRouteProgress", clamp01(NavigationModel.routeProgress))
    }

    function requestRouteToDestination() {
        var fromLat = NavigationFeed.currentLatitude
        var fromLon = NavigationFeed.currentLongitude
        OsrmRoute.requestRoute(fromLat, fromLon, destination.lat, destination.lon)
    }

    function pushAll() {
        pushRoute()
        pushVehicle()
        pushProgress()
        pushDestination()
    }

    function pushDestination() {
        runJsCall("setDestination", {
                      lat: destination.lat,
                      lng: destination.lon
                  })
    }

    Component.onCompleted: {
        mockRouteLngLat = buildMockRouteLngLat()
        requestRouteToDestination()
    }

    Connections {
        target: OsrmRoute
        function onRouteReady(path) {
            console.log("[NavWebMap] OSRM route received with", path.length, "points")
            navWebRoot.osrmRetryCount = 0
            routeLngLat = navWebRoot.geoVariantToLngLatArray(path)
            liveRouteReady = routeLngLat.length > 1
            pushRoute()
        }
        function onRouteFailed(error) {
            console.warn("[NavWebMap] OSRM routing failed:", error)
            liveRouteReady = false
            pushRoute()
            if (navWebRoot.osrmRetryCount < navWebRoot.osrmMaxRetries) {
                navWebRoot.osrmRetryCount++
                osrmRetryTimer.restart()
            }
        }
    }

    Timer {
        id: osrmRetryTimer
        interval: 3000
        repeat: false
        onTriggered: {
            console.log("[NavWebMap] Retrying OSRM route request (attempt", navWebRoot.osrmRetryCount + 1, ")")
            navWebRoot.requestRouteToDestination()
        }
    }

    Connections {
        target: NavigationModel
        function onRouteProgressChanged() {
            navWebRoot.pushProgress()
        }
    }

    Connections {
        target: NavigationFeed
        function onPositionUpdated() {
            navWebRoot.pushVehicle()
        }
        function onRouteLooped() {
            console.log("[NavWebMap] Route looped, re-pushing route")
            navWebRoot.pushRoute()
            navWebRoot.pushDestination()
        }
    }

    Item {
        id: mapArea
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        clip: true

        WebEngineView {
            id: mapWebView
            anchors.fill: parent
            url: "qrc:/web/maplibre_navigation.html"
            backgroundColor: "transparent"

            settings.javascriptEnabled: true
            settings.localContentCanAccessRemoteUrls: true
            settings.localContentCanAccessFileUrls: true
            settings.localStorageEnabled: true

            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineLoadRequest.LoadSucceededStatus) {
                    navWebRoot.pageReady = true
                    navWebRoot.pushAll()
                    return
                }

                if (loadRequest.status === WebEngineLoadRequest.LoadFailedStatus) {
                    navWebRoot.pageReady = false
                    console.error("Map WebEngine load failed:", loadRequest.errorString)
                }
            }
        }
    }

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
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.lineWidth = 2.8
                ctx.strokeStyle = "#7ef2d0"
                ctx.fillStyle = "#7ef2d0"
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
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
                text: NavigationModel.maneuver === NavigationModel.TurnLeft ? "turn left"
                      : NavigationModel.maneuver === NavigationModel.TurnRight ? "turn right"
                      : NavigationModel.maneuver === NavigationModel.UTurn ? "make a U-turn"
                      : NavigationModel.maneuver === NavigationModel.Arrive ? "arrive"
                      : "go straight"
                color: "#99b4cf"
                font.pixelSize: 10
            }
        }
    }

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
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.lineWidth = 2.8
                    ctx.strokeStyle = "#7ef2d0"
                    ctx.fillStyle = "#7ef2d0"
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(15, 22)
                    ctx.lineTo(15, 8)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(8, 13)
                    ctx.lineTo(15, 4)
                    ctx.lineTo(22, 13)
                    ctx.fill()
                }
            }

            Text {
                text: NavigationModel.nextStreet.length > 0 ? NavigationModel.nextStreet : NavigationModel.currentStreet
                color: "#f0f8ff"
                font.pixelSize: 16
                font.bold: true
            }

            Item { width: 1; height: 1 }

            Text {
                text: NavigationModel.maneuver === NavigationModel.TurnLeft ? "turn left"
                      : NavigationModel.maneuver === NavigationModel.TurnRight ? "turn right"
                      : NavigationModel.maneuver === NavigationModel.UTurn ? "make a U-turn"
                      : NavigationModel.maneuver === NavigationModel.Arrive ? "arrive"
                      : "go straight"
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
                text: nextDistance > 0 ? ("in " + (nextDistance >= 1000 ? (nextDistance / 1000).toFixed(1) + " km" : Math.round(nextDistance) + " m")) : ""
                color: "#8ea4bb"
                font.pixelSize: 12
            }
        }
    }
}
