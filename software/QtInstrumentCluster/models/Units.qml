pragma Singleton
import QtQuick 2.15

QtObject {
    readonly property string shortDistanceUnit: "m"
    readonly property string longDistanceUnit: "km"
    readonly property string speedUnit: "km/h"
    readonly property string fuelUsageUnit: "L/100km"
    readonly property string temperatureSymbol: "°C"

    readonly property int maximumSpeed: 200

    function toInt(value: real) : int {
        if (!isFinite(value))
            return 0
        return Math.round(value)
    }

    function metersToShortDistanceUnit(meters : real) : real {
        return meters
    }

    function kilometersToLongDistanceUnit(kilometers : real) : real {
        return kilometers
    }

    function longDistanceUnitToKilometers(value : real) : real {
        return value
    }

    function degreesToTemperatureUnit(degrees : real) : real {
        return degrees
    }
}
