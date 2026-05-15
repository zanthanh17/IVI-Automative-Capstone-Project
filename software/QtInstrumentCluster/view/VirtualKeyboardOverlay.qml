import QtQuick 2.12
import QtQuick.VirtualKeyboard 2.1
import QtQuick.VirtualKeyboard.Settings 2.1

Item {
    id: keyboardRoot
    property string keyboardLocale: "vi_VN"

    Component.onCompleted: {
        VirtualKeyboardSettings.locale = keyboardRoot.keyboardLocale
        console.log("[QML] Qt Virtual Keyboard locale:", VirtualKeyboardSettings.locale)
    }

    onKeyboardLocaleChanged: {
        VirtualKeyboardSettings.locale = keyboardRoot.keyboardLocale
    }

    InputPanel {
        id: virtualKeyboardPanel
        z: 1000
        anchors.left: parent.left
        anchors.right: parent.right
        y: Qt.inputMethod.visible ? parent.height - height : parent.height
        visible: Qt.inputMethod.visible
    }
}
