pragma Singleton
import QtQuick 2.15

QtObject {
    readonly property color highlighterGreen: "#4ade80";
    readonly property color highlighterRed: "#f87171";
    readonly property color brightBlue: "#0066ff";
    readonly property color lightPeriwinkle: "#cadfff";
    readonly property color darkBlue: "#001b4d";

    // Unified icon lighting profile to keep telltales/menu aligned with dashboard brightness.
    readonly property color iconInactiveBlue: "#7ea8ec";
    readonly property color iconActiveBlue: "#7fc6ff";
    readonly property real iconActiveBrightness: 0.56;
    readonly property real iconInactiveBrightness: 0.16;
    readonly property real iconActiveSaturation: 0.65;
    readonly property real iconInactiveSaturation: 0.20;
    readonly property real iconActiveContrast: 0.40;
    readonly property real iconInactiveContrast: 0.14;
    readonly property real iconActiveOpacity: 1.0;
    readonly property real iconInactiveOpacity: 0.84;
    readonly property real iconActiveShadowOpacity: 0.76;
    readonly property real iconInactiveShadowOpacity: 0.24;
    readonly property real iconShadowBlur: 0.42;
    readonly property real iconActiveShadowScale: 1.2;
    readonly property real iconInactiveShadowScale: 1.08;

    readonly property color orange: "#ff8e00";
}
