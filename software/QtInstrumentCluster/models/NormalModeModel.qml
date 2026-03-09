pragma Singleton
import QtQuick 2.15

QtObject {
    id: normalmodemodel

    enum Menu { MediaPlayerMenu, NavigationMenu, WeatherMenu, BluetoothMenu, CarStatusMenu, MenuCount }
    property int menu: NormalModeModel.MediaPlayerMenu

    // Quick-controls / system settings (mirrors of SystemSettingsController properties)
    // QML Setup page sẽ cập nhật đồng thời cả NormalModeModel.* và SystemSettings.*.
    property bool quickControlsEnabled: true
    property bool wifiEnabled: true
    property bool bluetoothEnabled: true
    property real volumeLevel: 0.6
    property real brightnessLevel: 0.7

    function nextMenu() {
        if (menu === NormalModeModel.MediaPlayerMenu) {
            menu = NormalModeModel.NavigationMenu
        }
        else if (menu === NormalModeModel.NavigationMenu) {
            menu = NormalModeModel.WeatherMenu
        }
        else if (menu === NormalModeModel.WeatherMenu) {
            menu = NormalModeModel.BluetoothMenu
        }
        else if (menu === NormalModeModel.BluetoothMenu) {
            menu = NormalModeModel.CarStatusMenu
        }
        else if (menu === NormalModeModel.CarStatusMenu) {
            menu = NormalModeModel.MediaPlayerMenu
        }
    }

    function previousMenu() {
        if (menu === NormalModeModel.MediaPlayerMenu) {
            menu = NormalModeModel.CarStatusMenu
        }
        else if (menu === NormalModeModel.NavigationMenu) {
            menu = NormalModeModel.MediaPlayerMenu
        }
        else if (menu === NormalModeModel.WeatherMenu) {
            menu = NormalModeModel.NavigationMenu
        }
        else if (menu === NormalModeModel.BluetoothMenu) {
            menu = NormalModeModel.WeatherMenu
        }
        else if (menu === NormalModeModel.CarStatusMenu) {
            menu = NormalModeModel.BluetoothMenu
        }
    }
}
