import QtQuick 2.12
import Style 1.0
import NormalModeModel 1.0
import BluetoothManager 1.0
import SystemSettings 1.0

NormalModeContentItem {
    id: setupRoot

    property bool wifiPopupOpen: false
    property bool bluetoothPopupOpen: false
    property string wifiPasswordInput: ""
    property string selectedWifiSSID: ""
    property bool showPasswordDialog: false
    property string wifiErrorMessage: ""

    Component.onCompleted: {
        SystemSettings.syncFromSystem()
        NormalModeModel.bluetoothEnabled = SystemSettings.bluetoothEnabled
        NormalModeModel.wifiEnabled = SystemSettings.wifiEnabled
        NormalModeModel.volumeLevel = SystemSettings.volumeLevel
        NormalModeModel.brightnessLevel = SystemSettings.brightnessLevel
    }

    Connections {
        target: BluetoothManager
        function onPoweredChanged() {
            NormalModeModel.bluetoothEnabled = BluetoothManager.powered
            if (SystemSettings.bluetoothEnabled !== BluetoothManager.powered)
                SystemSettings.bluetoothEnabled = BluetoothManager.powered
        }
    }

    Connections {
        target: SystemSettings
        function onWifiEnabledChanged() {
            NormalModeModel.wifiEnabled = SystemSettings.wifiEnabled
        }
        function onBluetoothEnabledChanged() {
            NormalModeModel.bluetoothEnabled = SystemSettings.bluetoothEnabled
        }
        function onVolumeLevelChanged() {
            NormalModeModel.volumeLevel = SystemSettings.volumeLevel
        }
        function onBrightnessLevelChanged() {
            NormalModeModel.brightnessLevel = SystemSettings.brightnessLevel
        }
        function onWifiConnectionResult(success, message) {
            if (success) {
                console.log("[Setup] Wi-Fi connected:", message)
                setupRoot.wifiErrorMessage = ""
                wifiPopupOpen = false
                showPasswordDialog = false
            } else if (message === "NEED_PASSWORD") {
                // Saved connection not found – prompt for password
                console.log("[Setup] Wi-Fi needs password for:", selectedWifiSSID)
                showPasswordDialog = true
                setupRoot.wifiErrorMessage = ""
                wifiPasswordInput = ""
                if (passwordInput) passwordInput.text = ""
            } else {
                console.log("[Setup] Wi-Fi connection failed:", message)
                setupRoot.wifiErrorMessage = message
            }
        }
    }

    // ==================== Main content ====================
    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        

        // Wi-Fi & Bluetooth buttons
        Row {
            spacing: 12
            anchors.horizontalCenter: parent.horizontalCenter

            // Wi-Fi button
            Rectangle {
                width: 140; height: 40
                radius: 20
                color: NormalModeModel.wifiEnabled ? Style.brightBlue : "#444"

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Image {
                        source: "qrc:/images/others/wifi.png"
                        width: 18; height: 18
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Wi-Fi ›"
                        color: "white"
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!NormalModeModel.wifiEnabled) {
                            NormalModeModel.wifiEnabled = true
                            SystemSettings.wifiEnabled = true
                        } else {
                            SystemSettings.scanWifiNetworks()
                            setupRoot.wifiPopupOpen = true
                        }
                    }
                    onPressAndHold: {
                        NormalModeModel.wifiEnabled = false
                        SystemSettings.wifiEnabled = false
                    }
                }
            }

            // Bluetooth button
            Rectangle {
                width: 160; height: 40
                radius: 20
                color: NormalModeModel.bluetoothEnabled ? Style.brightBlue : "#444"

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Image {
                        source: "qrc:/images/others/bluetooth.png"
                        width: 18; height: 18
                        sourceSize.width: 18
                        sourceSize.height: 18
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Bluetooth ›"
                        color: "white"
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!NormalModeModel.bluetoothEnabled) {
                            NormalModeModel.bluetoothEnabled = true
                            SystemSettings.bluetoothEnabled = true
                            BluetoothManager.setPowered(true)
                        } else {
                            setupRoot.bluetoothPopupOpen = true
                        }
                    }
                    onPressAndHold: {
                        NormalModeModel.bluetoothEnabled = false
                        SystemSettings.bluetoothEnabled = false
                        BluetoothManager.setPowered(false)
                    }
                }
            }
        }

        // ==================== Volume slider ====================
        Row {
            spacing: 10
            width: parent.width

            Image {
                source: "qrc:/images/others/volume.png"
                width: 22; height: 22
                sourceSize.width: 22
                sourceSize.height: 22
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                id: volumeTrack
                width: parent.width - 40
                height: 8
                radius: 4
                color: "#444"
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: volumeHandle.x + volumeHandle.width / 2
                    height: parent.height
                    radius: parent.radius
                    color: Style.brightBlue
                }

                Rectangle {
                    id: volumeHandle
                    width: 22; height: 22
                    radius: 11
                    color: Style.brightBlue
                    border.color: "white"
                    border.width: 2
                    y: (parent.height - height) / 2
                    x: NormalModeModel.volumeLevel * (parent.width - width)

                    MouseArea {
                        anchors.fill: parent
                        drag.target: parent
                        drag.axis: Drag.XAxis
                        drag.minimumX: 0
                        drag.maximumX: volumeTrack.width - volumeHandle.width

                        onPositionChanged: {
                            if (drag.active) {
                                var ratio = Math.max(0, Math.min(1,
                                    volumeHandle.x / (volumeTrack.width - volumeHandle.width)))
                                NormalModeModel.volumeLevel = ratio
                                SystemSettings.volumeLevel = ratio
                            }
                        }
                    }
                }
            }
        }

        // ==================== Brightness slider ====================
        Row {
            spacing: 10
            width: parent.width

            Image {
                source: "qrc:/images/others/brightness.png"
                width: 22; height: 22
                sourceSize.width: 22
                sourceSize.height: 22
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                id: brightnessTrack
                width: parent.width - 40
                height: 8
                radius: 4
                color: "#444"
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: brightnessHandle.x + brightnessHandle.width / 2
                    height: parent.height
                    radius: parent.radius
                    color: "#FFD600"
                }

                Rectangle {
                    id: brightnessHandle
                    width: 22; height: 22
                    radius: 11
                    color: "#FFD600"
                    border.color: "white"
                    border.width: 2
                    y: (parent.height - height) / 2
                    x: NormalModeModel.brightnessLevel * (parent.width - width)

                    MouseArea {
                        anchors.fill: parent
                        drag.target: parent
                        drag.axis: Drag.XAxis
                        drag.minimumX: 0
                        drag.maximumX: brightnessTrack.width - brightnessHandle.width

                        onPositionChanged: {
                            if (drag.active) {
                                var ratio = Math.max(0, Math.min(1,
                                    brightnessHandle.x / (brightnessTrack.width - brightnessHandle.width)))
                                NormalModeModel.brightnessLevel = ratio
                                SystemSettings.brightnessLevel = ratio
                            }
                        }
                    }
                }
            }
        }

        // ==================== Power controls ====================
        Rectangle {
            width: parent.width
            height: 1
            color: "#333"
        }

        Row {
            spacing: 10
            Image {
                source: "qrc:/images/others/power.png"
                width: 22; height: 22
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "Power"
                color: Style.textPrimary
                font.pixelSize: 14
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            spacing: 12
            anchors.horizontalCenter: parent.horizontalCenter

            // Reboot
            Rectangle {
                width: 110; height: 38
                radius: 12
                color: powerRebootArea.containsMouse ? "#555" : "#3a3a3a"

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                source: "qrc:/images/others/restart.png"
                width: 16; height: 16
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
                    Text {
                        text: "Reboot"
                        color: "white"
                        font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: powerRebootArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: powerConfirmDialog.show("reboot")
                }
            }

            // Shutdown
            Rectangle {
                width: 120; height: 38
                radius: 12
                color: powerShutdownArea.containsMouse ? "#6a2222" : "#4a2222"

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                source: "qrc:/images/others/shutdown.png"
                width: 16; height: 16
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
                    Text {
                        text: "Shutdown"
                        color: "#FF6666"
                        font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: powerShutdownArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: powerConfirmDialog.show("shutdown")
                }
            }

            // Restart App
            Rectangle {
                width: 130; height: 38
                radius: 12
                color: powerRestartArea.containsMouse ? "#555" : "#3a3a3a"

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "↺"
                        font.pixelSize: 16
                        color: Style.brightBlue
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Restart App"
                        color: "white"
                        font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: powerRestartArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: powerConfirmDialog.show("restart")
                }
            }
        }
    }

    // ==================== Power confirm dialog ====================
    Item {
        id: powerConfirmDialog
        anchors.fill: parent
        visible: false
        z: 60

        property string action: ""

        function show(act) {
            action = act
            visible = true
        }

        Rectangle {
            anchors.fill: parent
            color: "#AA000000"

            MouseArea {
                anchors.fill: parent
                onClicked: powerConfirmDialog.visible = false
            }

            Rectangle {
                width: 300; height: 160
                radius: 20
                color: Style.backgroundPanelSoft
                anchors.centerIn: parent

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        text: {
                            if (powerConfirmDialog.action === "reboot") return "Reboot system?"
                            if (powerConfirmDialog.action === "shutdown") return "Shutdown system?"
                            return "Restart application?"
                        }
                        color: Style.textPrimary
                        font.pixelSize: 16
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: {
                            if (powerConfirmDialog.action === "shutdown")
                                return "The system will power off."
                            if (powerConfirmDialog.action === "reboot")
                                return "The system will restart."
                            return "The app will close and relaunch."
                        }
                        color: Style.textSecondary
                        font.pixelSize: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Row {
                        spacing: 16
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            width: 100; height: 36
                            radius: 12
                            color: "#666"
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: "white"
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: powerConfirmDialog.visible = false
                            }
                        }

                        Rectangle {
                            width: 100; height: 36
                            radius: 12
                            color: powerConfirmDialog.action === "shutdown" ? "#cc3333" : Style.brightBlue
                            Text {
                                anchors.centerIn: parent
                                text: "Confirm"
                                color: "white"
                                font.pixelSize: 13
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    powerConfirmDialog.visible = false
                                    if (powerConfirmDialog.action === "reboot")
                                        SystemSettings.systemReboot()
                                    else if (powerConfirmDialog.action === "shutdown")
                                        SystemSettings.systemShutdown()
                                    else
                                        SystemSettings.restartApp()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================== Wi-Fi popup overlay ====================
    Rectangle {
        id: wifiPopup
        anchors.fill: parent
        color: "#80000000"
        visible: wifiPopupOpen
        z: 50

        MouseArea {
            anchors.fill: parent
            onClicked: {
                wifiPopupOpen = false
                showPasswordDialog = false
            }
        }

        Rectangle {
            width: 360
            height: showPasswordDialog ? 280 : 380
            radius: 22
            color: Style.backgroundPanelSoft
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                // Header
                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        width: 28; height: 28
                        radius: 14
                        color: "#444"
                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            color: "white"
                            font.pixelSize: 18
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (showPasswordDialog) {
                                    showPasswordDialog = false
                                } else {
                                    wifiPopupOpen = false
                                }
                            }
                        }
                    }

                    Column {
                        Text {
                            text: showPasswordDialog ? "Enter Password" : "Wi‑Fi Networks"
                            color: Style.textPrimary
                            font.pixelSize: 16
                            font.bold: true
                        }
                        Text {
                            text: {
                                if (SystemSettings.wifiConnecting)
                                    return SystemSettings.wifiStatusMessage
                                if (showPasswordDialog)
                                    return selectedWifiSSID
                                if (SystemSettings.connectedWifiSSID.length > 0)
                                    return "Connected: " + SystemSettings.connectedWifiSSID
                                return "Select a network"
                            }
                            color: SystemSettings.wifiConnecting ? "#FFD600" : Style.textSecondary
                            font.pixelSize: 11
                        }
                    }
                }

                // Password input
                Column {
                    visible: showPasswordDialog
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 8
                        color: "#333"
                        border.color: Style.brightBlue
                        border.width: 1

                        TextInput {
                            id: passwordInput
                            anchors.fill: parent
                            anchors.margins: 10
                            color: Style.textPrimary
                            font.pixelSize: 14
                            echoMode: TextInput.Password
                            clip: true
                            onTextChanged: wifiPasswordInput = text
                        }
                    }

                    Row {
                        spacing: 12
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            width: 100; height: 36
                            radius: 12
                            color: "#666"
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: "white"
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    showPasswordDialog = false
                                    setupRoot.wifiErrorMessage = ""
                                }
                            }
                        }

                        Rectangle {
                            width: 100; height: 36
                            radius: 12
                            color: SystemSettings.wifiConnecting ? "#888" : Style.brightBlue
                            opacity: SystemSettings.wifiConnecting ? 0.7 : 1.0
                            Text {
                                anchors.centerIn: parent
                                text: SystemSettings.wifiConnecting ? "Connecting…" : "Connect"
                                color: "white"
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !SystemSettings.wifiConnecting
                                onClicked: {
                                    setupRoot.wifiErrorMessage = ""
                                    SystemSettings.connectToWifi(selectedWifiSSID, wifiPasswordInput)
                                }
                            }
                        }
                    }

                    // Error message
                    Text {
                        visible: setupRoot.wifiErrorMessage.length > 0
                        text: "⚠ " + setupRoot.wifiErrorMessage
                        color: "#FF4444"
                        font.pixelSize: 11
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Network list
                ListView {
                    visible: !showPasswordDialog
                    width: parent.width
                    height: parent.height - 100
                    clip: true
                    model: SystemSettings.wifiNetworks
                    spacing: 2
                    enabled: !SystemSettings.wifiConnecting

                    delegate: Rectangle {
                        width: parent ? parent.width : 0
                        height: 40
                        radius: 8
                        color: wifiDelegateArea.containsMouse ? "#3a3a3a" : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: modelData.ssid || ""
                                color: Style.textPrimary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: parent.width * 0.45
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: (modelData.strength || "") + "%"
                                color: Style.textSecondary
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.secured ? "🔒" : ""
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: modelData.active || false
                                text: "✓"
                                color: Style.brightBlue
                                font.pixelSize: 14
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: wifiDelegateArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                selectedWifiSSID = modelData.ssid
                                setupRoot.wifiErrorMessage = ""
                                // Luôn thử reconnect saved trước (password rỗng)
                                // Nếu thất bại với NEED_PASSWORD → hiện dialog nhập mật khẩu
                                SystemSettings.connectToWifi(modelData.ssid, "")
                            }
                        }
                    }
                }

                // Status bar (connecting / error)
                Text {
                    visible: !showPasswordDialog && (SystemSettings.wifiConnecting || setupRoot.wifiErrorMessage.length > 0)
                    text: SystemSettings.wifiConnecting
                          ? ("⏳ " + SystemSettings.wifiStatusMessage)
                          : ("⚠ " + setupRoot.wifiErrorMessage)
                    color: SystemSettings.wifiConnecting ? "#FFD600" : "#FF4444"
                    font.pixelSize: 11
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                // Scan + Disconnect buttons
                Row {
                    visible: !showPasswordDialog
                    spacing: 12
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        width: 90; height: 32
                        radius: 10
                        color: Style.brightBlue
                        Text {
                            anchors.centerIn: parent
                            text: "Scan"
                            color: "white"
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: SystemSettings.scanWifiNetworks()
                        }
                    }

                    Rectangle {
                        visible: SystemSettings.connectedWifiSSID.length > 0
                        width: 110; height: 32
                        radius: 10
                        color: "#cc3333"
                        Text {
                            anchors.centerIn: parent
                            text: "Disconnect"
                            color: "white"
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: SystemSettings.disconnectWifi()
                        }
                    }
                }
            }
        }
    }

    // ==================== Bluetooth popup overlay ====================
    Rectangle {
        id: bluetoothPopup
        anchors.fill: parent
        color: "#80000000"
        visible: bluetoothPopupOpen
        z: 50

        MouseArea {
            anchors.fill: parent
            onClicked: bluetoothPopupOpen = false
        }

        Rectangle {
            width: 340
            height: 320
            radius: 22
            color: Style.backgroundPanelSoft
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Row {
                    spacing: 10

                    Rectangle {
                        width: 28; height: 28
                        radius: 14
                        color: "#444"
                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            color: "white"
                            font.pixelSize: 18
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: bluetoothPopupOpen = false
                        }
                    }

                    Column {
                        Text {
                            text: "Bluetooth Devices"
                            color: Style.textPrimary
                            font.pixelSize: 16
                            font.bold: true
                        }
                        Text {
                            text: BluetoothManager.powered ? "Powered On" : "Powered Off"
                            color: Style.textSecondary
                            font.pixelSize: 11
                        }
                    }
                }

                // Bluetooth ON/OFF toggle
                Row {
                    spacing: 10
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        text: "Bluetooth"
                        color: Style.textPrimary
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 50; height: 26
                        radius: 13
                        color: NormalModeModel.bluetoothEnabled ? Style.brightBlue : "#666"

                        Rectangle {
                            width: 20; height: 20
                            radius: 10
                            color: "white"
                            y: 3
                            x: NormalModeModel.bluetoothEnabled ? parent.width - width - 3 : 3

                            Behavior on x { NumberAnimation { duration: 200 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                var newState = !NormalModeModel.bluetoothEnabled
                                NormalModeModel.bluetoothEnabled = newState
                                SystemSettings.bluetoothEnabled = newState
                                BluetoothManager.setPowered(newState)
                            }
                        }
                    }
                }

                // Paired devices list
                ListView {
                    width: parent.width
                    height: parent.height - 120
                    clip: true
                    model: BluetoothManager.devices
                    spacing: 2

                    delegate: Rectangle {
                        width: parent ? parent.width : 0
                        height: 38
                        radius: 8
                        color: btDelegateArea.containsMouse ? "#3a3a3a" : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: modelData.name || "Unknown"
                                color: Style.textPrimary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: parent.width * 0.5
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.connected ? "Connected"
                                     : modelData.paired   ? "Paired"
                                     : ""
                                color: modelData.connected ? Style.brightBlue : Style.textSecondary
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: btDelegateArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (modelData.connected) {
                                    BluetoothManager.disconnectDevice(modelData.path)
                                } else if (modelData.paired) {
                                    BluetoothManager.connectDevice(modelData.path)
                                } else {
                                    BluetoothManager.pairDevice(modelData.path)
                                }
                            }
                        }
                    }
                }

                // Scan button
                Rectangle {
                    width: 90; height: 32
                    radius: 10
                    color: Style.brightBlue
                    anchors.horizontalCenter: parent.horizontalCenter
                    Text {
                        anchors.centerIn: parent
                        text: "Scan"
                        color: "white"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: BluetoothManager.startDiscovery()
                    }
                }
            }
        }
    }
}

