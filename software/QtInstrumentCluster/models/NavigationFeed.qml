pragma Singleton
import QtQuick 2.15

QtObject {
    id: navigationFeed

    // Source switch: keep the same signal pipeline and swap only producer.
    property bool useMockGps: true
    property bool running: true
    property bool loopMockRoute: true

    property int tickMs: 200
    property real mockSpeedKmh: 44.0

    readonly property var mockRoute: [
        { lat: 10.76350, lon: 106.70000 },
        { lat: 10.76350, lon: 106.70776 },
        { lat: 10.77431, lon: 106.70776 },
        { lat: 10.79500, lon: 106.70776 },
        { lat: 10.79500, lon: 106.71324 },
        { lat: 10.79905, lon: 106.71324 },
        { lat: 10.79743, lon: 106.71324 },
        { lat: 10.79743, lon: 106.74154 },
        { lat: 10.79743, lon: 106.74200 }
    ]

    readonly property real mockRouteLengthMeters: routeLengthMeters()

    property real mockTraveledMeters: 0
    property real currentLatitude: mockRoute.length > 0 ? mockRoute[0].lat : 0
    property real currentLongitude: mockRoute.length > 0 ? mockRoute[0].lon : 0
    property real currentHeadingDeg: 0
    property real currentSpeedKmh: 0

    signal positionUpdated(real latitude, real longitude, real speedKmh, real headingDeg, real timestampMs)
    signal sourceChanged(string source)
    signal routeLooped()

    function start() {
        running = true
    }

    function stop() {
        running = false
    }

    function resetMockRoute() {
        mockTraveledMeters = 0
        var startPoint = pointOnRoute(0)
        publishPosition(startPoint.lat, startPoint.lon, mockSpeedKmh, startPoint.heading, Date.now())
    }

    function injectHardwarePosition(latitude, longitude, speedKmh, headingDeg, timestampMs) {
        if (useMockGps) {
            return
        }
        publishPosition(latitude, longitude, speedKmh, headingDeg, timestampMs)
    }

    function publishPosition(latitude, longitude, speedKmh, headingDeg, timestampMs) {
        currentLatitude = latitude
        currentLongitude = longitude
        currentSpeedKmh = speedKmh
        currentHeadingDeg = headingDeg
        positionUpdated(latitude, longitude, speedKmh, headingDeg, timestampMs)
    }

    function toRad(degrees) {
        return degrees * Math.PI / 180.0
    }

    function toDeg(radians) {
        return radians * 180.0 / Math.PI
    }

    function haversineMeters(lat1, lon1, lat2, lon2) {
        var R = 6371000.0
        var dLat = toRad(lat2 - lat1)
        var dLon = toRad(lon2 - lon1)
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2)
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }

    function headingDeg(lat1, lon1, lat2, lon2) {
        var phi1 = toRad(lat1)
        var phi2 = toRad(lat2)
        var dLon = toRad(lon2 - lon1)
        var y = Math.sin(dLon) * Math.cos(phi2)
        var x = Math.cos(phi1) * Math.sin(phi2)
                - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLon)
        return (toDeg(Math.atan2(y, x)) + 360) % 360
    }

    function routeLengthMeters() {
        var total = 0
        for (var i = 0; i < mockRoute.length - 1; ++i) {
            total += haversineMeters(
                        mockRoute[i].lat, mockRoute[i].lon,
                        mockRoute[i + 1].lat, mockRoute[i + 1].lon)
        }
        return total
    }

    function pointOnRoute(distanceMeters) {
        if (mockRoute.length === 0) {
            return { lat: 0, lon: 0, heading: 0 }
        }
        if (mockRoute.length === 1) {
            return { lat: mockRoute[0].lat, lon: mockRoute[0].lon, heading: 0 }
        }

        var remaining = Math.max(0, distanceMeters)
        for (var i = 0; i < mockRoute.length - 1; ++i) {
            var from = mockRoute[i]
            var to = mockRoute[i + 1]
            var segment = haversineMeters(from.lat, from.lon, to.lat, to.lon)
            if (remaining <= segment || i === mockRoute.length - 2) {
                var t = segment > 0 ? Math.min(1, remaining / segment) : 0
                return {
                    lat: from.lat + (to.lat - from.lat) * t,
                    lon: from.lon + (to.lon - from.lon) * t,
                    heading: headingDeg(from.lat, from.lon, to.lat, to.lon)
                }
            }
            remaining -= segment
        }

        var last = mockRoute[mockRoute.length - 1]
        return { lat: last.lat, lon: last.lon, heading: 0 }
    }

    function advanceMock() {
        if (!running || !useMockGps || mockRouteLengthMeters <= 0) {
            return
        }

        var deltaMeters = Math.max(0.8, mockSpeedKmh * 1000.0 / 3600.0 * tickMs / 1000.0)
        var nextDistance = mockTraveledMeters + deltaMeters
        if (nextDistance >= mockRouteLengthMeters) {
            if (loopMockRoute) {
                nextDistance -= mockRouteLengthMeters
                routeLooped()
            } else {
                nextDistance = mockRouteLengthMeters
                stop()
            }
        }

        mockTraveledMeters = nextDistance
        var point = pointOnRoute(nextDistance)
        publishPosition(point.lat, point.lon, mockSpeedKmh, point.heading, Date.now())
    }

    onUseMockGpsChanged: {
        sourceChanged(useMockGps ? "mock" : "hardware")
        if (useMockGps) {
            resetMockRoute()
        }
    }

    property var _mockTimer: Timer {
        interval: navigationFeed.tickMs
        repeat: true
        running: navigationFeed.running && navigationFeed.useMockGps
        triggeredOnStart: true
        onTriggered: navigationFeed.advanceMock()
    }

    Component.onCompleted: {
        sourceChanged(useMockGps ? "mock" : "hardware")
        if (useMockGps) {
            resetMockRoute()
        }
    }
}
