pragma Singleton
import QtQuick 2.15
import VehicleGps 1.0

QtObject {
    id: navigationFeed

    property bool hasPositionFix: false
    property real currentLatitude: 0
    property real currentLongitude: 0
    property real currentHeadingDeg: 0
    property real currentSpeedKmh: 0

    signal positionUpdated(real latitude, real longitude, real speedKmh, real headingDeg, real timestampMs)
    signal sourceChanged(string source)

    function clearPositionFix() {
        hasPositionFix = false
        currentLatitude = 0
        currentLongitude = 0
        currentHeadingDeg = 0
        currentSpeedKmh = 0
    }

    function publishPosition(latitude, longitude, speedKmh, headingDeg, timestampMs) {
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
            return
        }

        hasPositionFix = true
        currentLatitude = latitude
        currentLongitude = longitude
        currentSpeedKmh = speedKmh
        currentHeadingDeg = headingDeg
        positionUpdated(latitude, longitude, speedKmh, headingDeg, timestampMs)
    }

    property var _gpsConnections: Connections {
        target: VehicleGps

        function onPositionChanged(latitude, longitude, speedKmh, headingDeg, timestampMs) {
            navigationFeed.publishPosition(latitude, longitude, speedKmh, headingDeg, timestampMs)
        }

        function onHasFixChanged() {
            if (!VehicleGps.hasFix) {
                navigationFeed.clearPositionFix()
            }
        }
    }

    Component.onCompleted: {
        sourceChanged("hardware")
        if (VehicleGps.hasFix) {
            publishPosition(VehicleGps.latitude,
                            VehicleGps.longitude,
                            VehicleGps.speedKmh,
                            VehicleGps.headingDeg,
                            VehicleGps.timestampMs)
        } else {
            clearPositionFix()
        }
    }
}
