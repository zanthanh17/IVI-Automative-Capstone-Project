import QtQuick 2.12
import TellTalesModel 1.0
import Style 1.0

Item {
    id: telltales
    width: 460
    height: 44


    Row {
        anchors.centerIn: parent
        spacing: 20

        TellTalesIndicator {
            source: "qrc:/images/telltales/turn_left.png"
            activeColor: "#2dff89"
            active: TellTalesModel.turnLeftActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
            blinking: TellTalesModel.turnLeftBlinking
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/beam.png"
            activeColor: "#2dff89"
            active: TellTalesModel.beamActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/high-beams.png"
            activeColor: "#37a0ff"
            active: TellTalesModel.highBeamsActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/parked.png"
            activeColor: "#ff4e5f"
            active: TellTalesModel.parkedActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/airbag.png"
            activeColor: "#ff4e5f"
            active: TellTalesModel.airbagActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
        }
        TellTalesIndicator {
            source: "qrc:/images/telltales/turn_right.png"
            activeColor: "#2dff89"
            active: TellTalesModel.turnRightActive
            indicatorOpacity: TellTalesModel.indicatorOpacity
            blinking: TellTalesModel.turnRightBlinking
        }
    }
}
