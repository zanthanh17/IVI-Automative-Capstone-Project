pragma Singleton
import QtQuick 2.15

QtObject {
    id: navigationModel

    /* === Maneuver types === */
    enum Maneuver { TurnLeft, TurnRight, GoStraight, UTurn, Arrive }

    /* === Navigation state === */
    property bool active: true
    property string currentStreet: ""
    property string nextStreet: ""
    property int maneuver: NavigationModel.GoStraight
    property real distanceToTurn: 0       // meters
    property string distanceToTurnText: ""
    property string eta: ""
    property string totalDistance: ""
    property int currentStep: 0

    /* === Simulated route === */
    readonly property var route: [
        { street: "Nguyen Van Linh",   next: "Pham Hung",          maneuver: NavigationModel.TurnRight,  dist: 850,  eta: "14:52", total: "12.3 km" },
        { street: "Pham Hung",         next: "Le Van Luong",       maneuver: NavigationModel.TurnLeft,   dist: 1200, eta: "14:55", total: "11.1 km" },
        { street: "Le Van Luong",      next: "Nguyen Huu Tho",     maneuver: NavigationModel.GoStraight, dist: 2300, eta: "14:59", total: "9.5 km"  },
        { street: "Nguyen Huu Tho",    next: "Ton Duc Thang",      maneuver: NavigationModel.TurnRight,  dist: 600,  eta: "15:03", total: "7.2 km"  },
        { street: "Ton Duc Thang",     next: "Hai Ba Trung",       maneuver: NavigationModel.TurnLeft,   dist: 450,  eta: "15:07", total: "5.0 km"  },
        { street: "Hai Ba Trung",      next: "Dien Bien Phu",      maneuver: NavigationModel.UTurn,      dist: 180,  eta: "15:10", total: "3.1 km"  },
        { street: "Dien Bien Phu",     next: "Destination",        maneuver: NavigationModel.GoStraight, dist: 3100, eta: "15:15", total: "1.5 km"  },
        { street: "Dien Bien Phu",     next: "123 Pasteur, Q.1",   maneuver: NavigationModel.Arrive,     dist: 50,   eta: "15:18", total: "50 m"    }
    ]

    /* === Distance countdown simulation === */
    property real _countdownDist: 0
    readonly property int _stepDurationMs: 6000   // time per route step
    readonly property int _tickMs: 200

    /* Format distance: meters or km */
    function formatDistance(meters) {
        if (meters >= 1000) {
            return (meters / 1000).toFixed(1) + " km"
        }
        return Math.round(meters) + " m"
    }

    function loadStep(idx) {
        var step = route[idx % route.length]
        currentStreet     = step.street
        nextStreet        = step.next
        maneuver          = step.maneuver
        distanceToTurn    = step.dist
        _countdownDist    = step.dist
        distanceToTurnText = formatDistance(step.dist)
        eta               = step.eta
        totalDistance      = step.total
    }

    /* === Timers === */
    property var _stepTimer: Timer {
        interval: navigationModel._stepDurationMs
        repeat: true
        running: navigationModel.active
        onTriggered: {
            navigationModel.currentStep = (navigationModel.currentStep + 1) % navigationModel.route.length
            navigationModel.loadStep(navigationModel.currentStep)
        }
    }

    property var _countdownTimer: Timer {
        interval: navigationModel._tickMs
        repeat: true
        running: navigationModel.active
        onTriggered: {
            var decrement = navigationModel._countdownDist / (navigationModel._stepDurationMs / navigationModel._tickMs)
            navigationModel.distanceToTurn = Math.max(0, navigationModel.distanceToTurn - decrement)
            navigationModel.distanceToTurnText = navigationModel.formatDistance(navigationModel.distanceToTurn)
        }
    }

    Component.onCompleted: loadStep(0)
}
