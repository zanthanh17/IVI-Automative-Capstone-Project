pragma Singleton
import QtQuick 2.15

QtObject {
    id: normalmodemodel

    enum Menu { MediaPlayerMenu, NavigationMenu, WeatherMenu, BluetoothMenu, CarStatusMenu, MenuCount }
    property int menu: NormalModeModel.MediaPlayerMenu

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
