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
    readonly property real initialOdo: 300
    property real odo: initialOdo

    readonly property real fullRange: 895
    property real range: fullRange - odo
    property real speed: 0
    property real rpm: 0
    property string gearShiftText: "P"
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

    property bool laneAssistCarMoving: speed > minMovingSpeedKph
    readonly property real minMovingSpeedKph: 0.3
    readonly property real rangeSmoothingFactor: 0.22
    property double lastHardwareTickMs: Date.now()

    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function syncRangeFromFuel(immediate) {
        var targetRange = clamp01(fuelLevel) * fullRange
        if (immediate) {
            range = targetRange
            return
        }
        range = range + (targetRange - range) * rangeSmoothingFactor
    }

    Component.onCompleted: {
        MainModelData.modelUpdated.connect(modelUpdated);
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
            MainModel.gearShiftText = MainModelData.gearText
        }
    }

    onFuelLevelChanged: {
        if (MainModelData.hardwareConnected) {
            syncRangeFromFuel(false)
        }
    }

    property Connections hardwareConnection: Connections {
        target: MainModelData
        function onHardwareConnectedChanged() {
            mainmodel.lastHardwareTickMs = Date.now()
            if (MainModelData.hardwareConnected) {
                mainmodel.syncRangeFromFuel(true)
            }
        }
    }

    property Timer hardwareTelemetryTimer: Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            var nowMs = Date.now()
            var dtMs = Math.max(0, nowMs - mainmodel.lastHardwareTickMs)
            mainmodel.lastHardwareTickMs = nowMs

            if (!MainModelData.hardwareConnected) {
                return
            }

            if (mainmodel.speed > mainmodel.minMovingSpeedKph) {
                mainmodel.odo = mainmodel.odo + (mainmodel.speed * dtMs / 3600000.0)
            }

            mainmodel.syncRangeFromFuel(false)
        }
    }
}
