pragma Singleton
import QtQuick 2.15
import NavigationFeed 1.0

QtObject {
    id: navigationModel

    enum Maneuver { TurnLeft, TurnRight, GoStraight, UTurn, Arrive }

    property bool active: false
    property string source: "hardware"

    property string currentStreet: ""
    property string nextStreet: ""
    property int maneuver: NavigationModel.GoStraight
    property real distanceToTurn: 0
    property string distanceToTurnText: "0 m"
    property string eta: "--:--"
    property string totalDistance: "0 m"
    property int currentStep: 0
    property real routeProgress: 0

    property real traveledMeters: 0
    property real remainingMeters: 0

    property bool hasFix: false
    property real latitude: 0
    property real longitude: 0
    property real speedKmh: 0
    property real headingDeg: 0

    property real _lastLat: 0
    property real _lastLon: 0
    property real _lastTimestampMs: 0

    property var route: []

    property real totalRouteMeters: computeTotalRouteMeters()

    function toRad(degrees) {
        return degrees * Math.PI / 180.0
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

    function computeTotalRouteMeters() {
        if (!route) return 0
        var total = 0
        for (var i = 0; i < route.length; ++i) {
            total += route[i].dist
        }
        return total
    }

    function setRouteSteps(stepsVariantList) {
        if (!stepsVariantList || stepsVariantList.length === 0) {
            route = []
            totalRouteMeters = 0
            resetRouteProgress()
            return
        }
        
        // The items inside stepsVariantList correspond to the QVariantMap {street, next, maneuver, dist}
        route = stepsVariantList
        totalRouteMeters = computeTotalRouteMeters()
        resetRouteProgress()
    }

    function formatDistance(meters) {
        if (meters >= 1000) {
            return (meters / 1000).toFixed(1) + " km"
        }
        return Math.round(Math.max(0, meters)) + " m"
    }

    function computeEta(remainingDistanceMeters, currentSpeedKmh) {
        if (remainingDistanceMeters <= 0) {
            return "Arrived"
        }

        var effectiveSpeed = Math.max(20, currentSpeedKmh)
        var minutes = remainingDistanceMeters / (effectiveSpeed * 1000.0 / 60.0)
        var arrival = new Date(Date.now() + minutes * 60000.0)
        return Qt.formatTime(arrival, "hh:mm")
    }

    function resetRouteProgress() {
        active = totalRouteMeters > 0
        hasFix = false
        traveledMeters = 0
        remainingMeters = totalRouteMeters
        updateFromDistance(0)
    }

    onRouteChanged: {
        totalRouteMeters = computeTotalRouteMeters()
    }

    function updateFromDistance(distanceMeters) {
        var clamped = Math.min(Math.max(distanceMeters, 0), totalRouteMeters)
        traveledMeters = clamped
        remainingMeters = Math.max(0, totalRouteMeters - clamped)
        routeProgress = totalRouteMeters > 0 ? clamped / totalRouteMeters : 0

        var cumulative = 0
        var stepIndex = route && route.length > 0 ? route.length - 1 : 0
        if (route && route.length > 0) {
            for (var i = 0; i < route.length; ++i) {
                var nextCumulative = cumulative + route[i].dist
                if (clamped < nextCumulative) {
                    stepIndex = i
                    break
                }
                cumulative = nextCumulative
            }
        }

        currentStep = stepIndex
        if (!route || route.length === 0) {
            currentStreet = ""
            nextStreet = ""
            maneuver = NavigationModel.Arrive
            distanceToTurn = 0
            distanceToTurnText = ""
            totalDistance = formatDistance(remainingMeters)
            eta = computeEta(remainingMeters, speedKmh)
            return
        }

        var step = route[stepIndex]
        var distanceWithinStep = clamped - cumulative
        var remainingStep = Math.max((step.dist || 0) - distanceWithinStep, 0)

        currentStreet = step.street || ""
        nextStreet = step.next || ""
        maneuver = remainingMeters <= 8 ? NavigationModel.Arrive : step.maneuver

        distanceToTurn = remainingStep
        distanceToTurnText = formatDistance(remainingStep)
        totalDistance = formatDistance(remainingMeters)
        eta = computeEta(remainingMeters, speedKmh)
    }

    function updateFromPosition(lat, lon, speed, heading, timestampMs) {
        latitude = lat
        longitude = lon
        speedKmh = speed
        headingDeg = heading

        if (!active) {
            return
        }

        if (!hasFix) {
            hasFix = true
            _lastLat = lat
            _lastLon = lon
            _lastTimestampMs = timestampMs
            updateFromDistance(traveledMeters)
            return
        }

        var deltaMeters = haversineMeters(_lastLat, _lastLon, lat, lon)
        var dtSeconds = Math.max(0.05, (timestampMs - _lastTimestampMs) / 1000.0)
        var maxReasonable = Math.max(10, Math.max(speed, speedKmh) * 1000.0 / 3600.0 * dtSeconds * 3.0)
        deltaMeters = Math.min(deltaMeters, maxReasonable, 120)

        if (deltaMeters > 0.35) {
            traveledMeters += deltaMeters
        }

        if (traveledMeters >= totalRouteMeters) {
            traveledMeters = totalRouteMeters
            active = false
            updateFromDistance(traveledMeters)
        } else {
            updateFromDistance(traveledMeters)
        }

        _lastLat = lat
        _lastLon = lon
        _lastTimestampMs = timestampMs
    }

    property var _feedConnections: Connections {
        target: NavigationFeed

        function onPositionUpdated(latitude, longitude, speedKmh, headingDeg, timestampMs) {
            navigationModel.updateFromPosition(latitude, longitude, speedKmh, headingDeg, timestampMs)
        }

        function onSourceChanged(source) {
            navigationModel.source = source
            navigationModel.resetRouteProgress()
        }
    }

    Component.onCompleted: {
        source = "hardware"
        resetRouteProgress()
    }
}
