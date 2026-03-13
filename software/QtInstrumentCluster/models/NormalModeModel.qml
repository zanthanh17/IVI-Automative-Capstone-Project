pragma Singleton
import QtQuick 2.15

QtObject {
    id: normalmodemodel

    enum Menu { MediaPlayerMenu, NavigationMenu, WeatherMenu, CameraMenu, CarStatusMenu, MenuCount }
    property int menu: NormalModeModel.MediaPlayerMenu

    // Quick-controls / system settings (mirrors of SystemSettingsController properties)
    // QML Setup page sẽ cập nhật đồng thời cả NormalModeModel.* và SystemSettings.*.
    property bool quickControlsEnabled: true
    property bool wifiEnabled: true
    property bool bluetoothEnabled: true
    property real volumeLevel: 0.6
    property real brightnessLevel: 0.7
    

    function nextMenu() {
        menu = (menu + 1) % NormalModeModel.MenuCount
    }

    function previousMenu() {
        menu = (menu - 1 + NormalModeModel.MenuCount) % NormalModeModel.MenuCount
    }
}
