pragma Singleton
import QtQuick 2.15
import Units 1.0
import MainModelData 1.0
import QtQuick.Controls 2.15

QtObject {
    id: mainmodel

    enum ClusterMode { ModeNormal, ModeSport, ModeEco }
    property int clusterMode: MainModel.ModeNormal
    property bool introSequenceStarted: false
    property bool introSequenceCompleted: false

    property int speedLimitWarning: SpeedLimitValues.Slow
    readonly property int initialOdo: 300
    property real odo: initialOdo

    readonly property int fullRange: 895
    property real range: fullRange - odo
    property real speed: 0
    property real rpm: 0
    property string gearShiftText: "P"
    property bool autoGearEnabled: true
    readonly property real gearReverseThresholdKph: -0.4
    readonly property real gearDriveThresholdKph: 0.8
    readonly property real gearNeutralRpmThreshold: 1400
    property real temp: 0

    readonly property real initialFuelLevel: range / fullRange
    readonly property real initialBatteryLevel: 0.2

    property real fuelLevel: initialFuelLevel
    property real batteryLevel: initialBatteryLevel

    readonly property int maxSpeed: Units.longDistanceUnitToKilometers(Units.maximumSpeed)
    readonly property int maxRpm: 7000

    property bool telltalesVisible: true
    property bool clusterVisible: true
    property real clusterOpacity: 0
    property real gaugesOpacity: 0

    readonly property int clusterOpacityChangeDuration: 750
    readonly property int gaugesOpacityChangeDuration: 750;

    readonly property int gaugesValueChangeDurationNormal: 500
    readonly property int gaugesValueChangeDurationSlow: 1250
    property int gaugesValueChangeDuration: gaugesValueChangeDurationNormal

    property bool laneAssistCarMoving: MainModelData.hardwareConnected
    onSpeedChanged: updateAutomaticGear()
    onRpmChanged: updateAutomaticGear()

    function normalizeGear(text) {
        var gear = (text || "").toString().trim().toUpperCase()
        if (gear === "R" || gear === "P" || gear === "N" || gear === "D")
            return gear
        return ""
    }

    function inferAutomaticGear(speedValue, rpmValue) {
        if (speedValue <= gearReverseThresholdKph)
            return "R"
        if (speedValue >= gearDriveThresholdKph)
            return "D"
        if (rpmValue > gearNeutralRpmThreshold)
            return "N"
        return "P"
    }

    function updateAutomaticGear() {
        if (!autoGearEnabled || MainModelData.hardwareConnected)
            return

        var incomingGear = normalizeGear(MainModelData.gearText)
        if (incomingGear !== "") {
            MainModel.gearShiftText = incomingGear
            return
        }

        MainModel.gearShiftText = inferAutomaticGear(MainModel.speed, MainModel.rpm)
    }

    Component.onCompleted: {
        MainModelData.modelUpdated.connect(modelUpdated);

        // Restore persisted telemetry from C++ singleton on app start.
        if (isFinite(MainModelData.odo) && MainModelData.odo >= 0)
            MainModel.odo = MainModelData.odo
        if (isFinite(MainModelData.range) && MainModelData.range >= 0)
            MainModel.range = MainModelData.range

        MainModelData.setOdo(MainModel.odo)
        MainModelData.setRange(MainModel.range)
        updateAutomaticGear()
    }

    property Timer odometerTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            // Integrate odometer from current speed (km/h -> km each second).
            if (MainModel.speed <= 0)
                return

            var deltaKm = MainModel.speed / 3600.0
            MainModel.odo = MainModel.odo + deltaKm
            MainModel.range = Math.max(0, MainModel.range - deltaKm)
            MainModelData.setOdo(MainModel.odo)
            MainModelData.setRange(MainModel.range)

            // Keep fuel gauge coherent in simulation mode.
            if (!MainModelData.hardwareConnected) {
                MainModel.fuelLevel = Math.max(0, Math.min(1, MainModel.range / MainModel.fullRange))
            }
        }
    }

    function modelUpdated(){
        TellTalesModel.qtLogoOpacity = 0

        /* Chỉ copy từ MainModelData khi KHÔNG có hardware
         * Khi hardware connected, data đi thẳng qua Connections block trong main.qml */
        if (!MainModelData.hardwareConnected) {
            MainModel.speed = MainModelData.speed
            MainModel.rpm = MainModelData.rpm
            MainModel.odo = MainModelData.odo
            MainModel.range = MainModelData.range
            MainModel.fuelLevel = MainModelData.fuelLevel
            MainModel.batteryLevel = MainModelData.batteryLevel
            updateAutomaticGear()
        }
    }
}
