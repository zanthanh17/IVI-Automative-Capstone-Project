#include "bluetoothcontroller.h"

#include <algorithm>
#include <utility>

#include <QDebug>
#include <QTimer>

#if defined(Q_OS_LINUX)
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusContext>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusVariant>
#endif

#if defined(Q_OS_LINUX)
namespace {
using DBusProperties = QVariantMap;
using DBusInterfaceMap = QMap<QString, DBusProperties>;
using DBusManagedObjects = QMap<QDBusObjectPath, DBusInterfaceMap>;

const QDBusArgument &operator>>(const QDBusArgument &argument, DBusInterfaceMap &map)
{
    map.clear();
    argument.beginMap();
    while (!argument.atEnd()) {
        QString interfaceName;
        DBusProperties properties;
        argument.beginMapEntry();
        argument >> interfaceName >> properties;
        argument.endMapEntry();
        map.insert(interfaceName, properties);
    }
    argument.endMap();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, DBusManagedObjects &map)
{
    map.clear();
    argument.beginMap();
    while (!argument.atEnd()) {
        QDBusObjectPath objectPath;
        DBusInterfaceMap interfaceMap;
        argument.beginMapEntry();
        argument >> objectPath >> interfaceMap;
        argument.endMapEntry();
        map.insert(objectPath, interfaceMap);
    }
    argument.endMap();
    return argument;
}

bool uuidLooksAudio(const QString &uuid)
{
    const QString lower = uuid.toLower();
    return lower.startsWith(QStringLiteral("0000110b"))
        || lower.startsWith(QStringLiteral("0000110a"))
        || lower.startsWith(QStringLiteral("0000110e"))
        || lower.startsWith(QStringLiteral("0000110c"))
        || lower.startsWith(QStringLiteral("0000111e"))
        || lower.startsWith(QStringLiteral("0000111f"))
        || lower.startsWith(QStringLiteral("00001108"));
}
} // namespace

class BluezPairAgent : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")

public:
    explicit BluezPairAgent(BluetoothController *controller)
        : QObject(controller)
        , m_controller(controller)
    {
    }

public slots:
    void Release() {}
    void Cancel() {}

    QString RequestPinCode(const QDBusObjectPath &device)
    {
        if (!allow(device.path())) {
            reject(QStringLiteral("Pair mode disabled"));
            return QString();
        }
        return QStringLiteral("0000");
    }

    quint32 RequestPasskey(const QDBusObjectPath &device)
    {
        if (!allow(device.path())) {
            reject(QStringLiteral("Pair mode disabled"));
            return 0;
        }
        return 0;
    }

    void DisplayPinCode(const QDBusObjectPath &device, const QString &pincode)
    {
        Q_UNUSED(device)
        Q_UNUSED(pincode)
    }

    void DisplayPasskey(const QDBusObjectPath &device, quint32 passkey, quint16 entered)
    {
        Q_UNUSED(device)
        Q_UNUSED(passkey)
        Q_UNUSED(entered)
    }

    void RequestConfirmation(const QDBusObjectPath &device, quint32 passkey)
    {
        Q_UNUSED(passkey)
        if (!allow(device.path())) {
            reject(QStringLiteral("Pair request not active in UI"));
        }
    }

    void RequestAuthorization(const QDBusObjectPath &device)
    {
        if (!allow(device.path())) {
            reject(QStringLiteral("Pair request not active in UI"));
        }
    }

    void AuthorizeService(const QDBusObjectPath &device, const QString &uuid)
    {
        Q_UNUSED(uuid)
        if (!allow(device.path())) {
            reject(QStringLiteral("Service not authorized"));
        }
    }

private:
    bool allow(const QString &path) const
    {
        return m_controller && m_controller->allowAgentForDevice(path);
    }

    void reject(const QString &message)
    {
        if (calledFromDBus()) {
            sendErrorReply(QStringLiteral("org.bluez.Error.Rejected"), message);
        }
    }

    BluetoothController *m_controller = nullptr;
};
#endif

BluetoothController *BluetoothController::instance()
{
    static BluetoothController *s_instance = nullptr;
    if (!s_instance) {
        s_instance = new BluetoothController();
    }
    return s_instance;
}

BluetoothController::BluetoothController(QObject *parent)
    : QObject(parent)
    , m_settings(QStringLiteral("DES"), QStringLiteral("QtInstrumentCluster"))
{
    m_lastConnectedAddress = m_settings.value(QStringLiteral("bluetooth/last_connected_address")).toString();

#if defined(Q_OS_LINUX)
    m_supported = hasBluezService();
    if (m_supported) {
        subscribeBluezSignals();
        queryManagedObjects();
        QTimer::singleShot(2000, this, &BluetoothController::reconnectLastDevice);
    } else {
        setLastError(QStringLiteral("BlueZ service unavailable"));
    }
#else
    m_supported = false;
    setLastError(QStringLiteral("Bluetooth controller is available on Linux/Pi only"));
#endif
}

BluetoothController::~BluetoothController()
{
#if defined(Q_OS_LINUX)
    unregisterAgent();
#endif
}

bool BluetoothController::supported() const
{
    return m_supported;
}

bool BluetoothController::adapterPresent() const
{
    return m_adapterPresent;
}

bool BluetoothController::powered() const
{
    return m_powered;
}

bool BluetoothController::discovering() const
{
    return m_discovering;
}

bool BluetoothController::pairMode() const
{
    return m_pairMode;
}

QString BluetoothController::lastError() const
{
    return m_lastError;
}

QVariantList BluetoothController::devices() const
{
    return m_devices;
}

BluetoothController::DeviceInfo *BluetoothController::findDevice(const QString &path)
{
    auto it = m_deviceMap.find(path);
    if (it == m_deviceMap.end()) {
        return nullptr;
    }
    return &it.value();
}

const BluetoothController::DeviceInfo *BluetoothController::findDevice(const QString &path) const
{
    const auto it = m_deviceMap.constFind(path);
    if (it == m_deviceMap.cend()) {
        return nullptr;
    }
    return &it.value();
}

void BluetoothController::setDeviceBusy(const QString &path, bool busy)
{
    DeviceInfo *device = findDevice(path);
    if (!device || device->busy == busy) {
        return;
    }
    device->busy = busy;
    rebuildDeviceList();
}

void BluetoothController::setLastError(const QString &message)
{
    if (m_lastError == message) {
        return;
    }
    m_lastError = message;
    emit lastErrorChanged();
}

void BluetoothController::rememberLastConnected(const QString &address)
{
    if (address.isEmpty()) {
        return;
    }
    if (m_lastConnectedAddress.compare(address, Qt::CaseInsensitive) == 0) {
        return;
    }
    m_lastConnectedAddress = address.toUpper();
    m_settings.setValue(QStringLiteral("bluetooth/last_connected_address"), m_lastConnectedAddress);
}

bool BluetoothController::allowAgentForDevice(const QString &path) const
{
    if (!m_pairMode) {
        return false;
    }
    if (m_pairTargetPath.isEmpty()) {
        return true;
    }
    return m_pairTargetPath == path;
}

void BluetoothController::rebuildDeviceList()
{
    QList<DeviceInfo> sorted = m_deviceMap.values();
    std::sort(sorted.begin(), sorted.end(), [](const DeviceInfo &left, const DeviceInfo &right) {
        if (left.connected != right.connected) {
            return left.connected > right.connected;
        }
        if (left.paired != right.paired) {
            return left.paired > right.paired;
        }
        return left.name.toLower() < right.name.toLower();
    });

    QVariantList next;
    next.reserve(sorted.size());
    for (const DeviceInfo &device : std::as_const(sorted)) {
        QVariantMap row;
        row.insert(QStringLiteral("path"), device.path);
        row.insert(QStringLiteral("address"), device.address);
        row.insert(QStringLiteral("name"), device.name);
        row.insert(QStringLiteral("paired"), device.paired);
        row.insert(QStringLiteral("trusted"), device.trusted);
        row.insert(QStringLiteral("connected"), device.connected);
        row.insert(QStringLiteral("audioCapable"), device.audioCapable);
        row.insert(QStringLiteral("rssi"), device.rssi);
        row.insert(QStringLiteral("busy"), device.busy);
        row.insert(QStringLiteral("isLastConnected"),
                   !m_lastConnectedAddress.isEmpty()
                   && device.address.compare(m_lastConnectedAddress, Qt::CaseInsensitive) == 0);
        next.push_back(row);
    }

    if (m_devices != next) {
        m_devices = next;
        emit devicesChanged();
    }
}

void BluetoothController::refresh()
{
#if defined(Q_OS_LINUX)
    queryManagedObjects();
#else
    setLastError(QStringLiteral("Bluetooth controller is available on Linux/Pi only"));
#endif
}

void BluetoothController::setPowered(bool on)
{
#if defined(Q_OS_LINUX)
    if (!m_supported) {
        setLastError(QStringLiteral("BlueZ service unavailable"));
        return;
    }
    if (!m_adapterPresent || m_adapterPath.isEmpty()) {
        setLastError(QStringLiteral("No Bluetooth adapter found"));
        return;
    }

    setAdapterProperty(QStringLiteral("Powered"), on, [this, on](bool ok) {
        if (!ok) {
            return;
        }
        if (!on && m_pairMode) {
            m_pairMode = false;
            m_pairTargetPath.clear();
            emit pairModeChanged();
            unregisterAgent();
        }
        queryManagedObjects();
    });
#else
    Q_UNUSED(on)
    setLastError(QStringLiteral("Bluetooth controller is available on Linux/Pi only"));
#endif
}

void BluetoothController::setPairMode(bool enabled)
{
#if defined(Q_OS_LINUX)
    if (!m_supported) {
        setLastError(QStringLiteral("BlueZ service unavailable"));
        return;
    }
    if (!m_adapterPresent || m_adapterPath.isEmpty()) {
        setLastError(QStringLiteral("No Bluetooth adapter found"));
        return;
    }
    if (!m_powered) {
        setLastError(QStringLiteral("Turn Bluetooth ON first"));
        return;
    }
    if (m_pairMode == enabled) {
        return;
    }

    if (enabled) {
        registerAgentIfNeeded();
        m_pairMode = true;
        emit pairModeChanged();
        setAdapterProperty(QStringLiteral("Pairable"), true);
        setAdapterProperty(QStringLiteral("Discoverable"), true);
    } else {
        m_pairMode = false;
        m_pairTargetPath.clear();
        emit pairModeChanged();
        setAdapterProperty(QStringLiteral("Discoverable"), false);
        setAdapterProperty(QStringLiteral("Pairable"), false, [this](bool) {
            unregisterAgent();
        });
    }
#else
    Q_UNUSED(enabled)
    setLastError(QStringLiteral("Bluetooth controller is available on Linux/Pi only"));
#endif
}

void BluetoothController::startDiscovery()
{
#if defined(Q_OS_LINUX)
    if (!m_supported) {
        setLastError(QStringLiteral("BlueZ service unavailable"));
        return;
    }
    if (!m_powered) {
        setLastError(QStringLiteral("Turn Bluetooth ON first"));
        return;
    }
    if (!m_adapterPresent || m_adapterPath.isEmpty()) {
        setLastError(QStringLiteral("No Bluetooth adapter found"));
        return;
    }

    QDBusInterface adapterIface(QStringLiteral("org.bluez"),
                                m_adapterPath,
                                QStringLiteral("org.bluez.Adapter1"),
                                QDBusConnection::systemBus());
    if (!adapterIface.isValid()) {
        setLastError(QStringLiteral("Bluetooth adapter interface is invalid"));
        return;
    }

    QDBusPendingCall call = adapterIface.asyncCall(QStringLiteral("StartDiscovery"));
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        const QDBusMessage reply = watcher->reply();
        if (reply.type() == QDBusMessage::ErrorMessage) {
            setLastError(QStringLiteral("Failed to start scan: %1").arg(reply.errorMessage()));
        } else {
            setLastError(QString());
        }
        watcher->deleteLater();
        queryManagedObjects();
    });
#else
    setLastError(QStringLiteral("Bluetooth controller is available on Linux/Pi only"));
#endif
}

void BluetoothController::stopDiscovery()
{
#if defined(Q_OS_LINUX)
    if (!m_supported || !m_adapterPresent || m_adapterPath.isEmpty()) {
        return;
    }
    QDBusInterface adapterIface(QStringLiteral("org.bluez"),
                                m_adapterPath,
                                QStringLiteral("org.bluez.Adapter1"),
                                QDBusConnection::systemBus());
    if (!adapterIface.isValid()) {
        return;
    }

    QDBusPendingCall call = adapterIface.asyncCall(QStringLiteral("StopDiscovery"));
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        watcher->deleteLater();
        queryManagedObjects();
    });
#endif
}

void BluetoothController::pairDevice(const QString &path)
{
#if defined(Q_OS_LINUX)
    if (!m_powered) {
        setLastError(QStringLiteral("Turn Bluetooth ON first"));
        return;
    }
    if (!findDevice(path)) {
        setLastError(QStringLiteral("Device not found"));
        return;
    }

    if (!m_pairMode) {
        setPairMode(true);
        if (!m_pairMode) {
            return;
        }
    }

    m_pairTargetPath = path;
    setDeviceBusy(path, true);
    callDeviceMethod(path, QStringLiteral("Pair"), {}, [this, path](bool ok) {
        if (!ok) {
            setDeviceBusy(path, false);
            return;
        }

        QDBusInterface propertiesIface(QStringLiteral("org.bluez"),
                                       path,
                                       QStringLiteral("org.freedesktop.DBus.Properties"),
                                       QDBusConnection::systemBus());
        if (!propertiesIface.isValid()) {
            setDeviceBusy(path, false);
            queryManagedObjects();
            return;
        }

        QList<QVariant> arguments;
        arguments << QVariant::fromValue(QStringLiteral("org.bluez.Device1"))
                  << QVariant::fromValue(QStringLiteral("Trusted"))
                  << QVariant::fromValue(QDBusVariant(true));

        QDBusPendingCall call = propertiesIface.asyncCallWithArgumentList(QStringLiteral("Set"), arguments);
        auto *watcher = new QDBusPendingCallWatcher(call, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, path]() {
            const QDBusMessage reply = watcher->reply();
            if (reply.type() == QDBusMessage::ErrorMessage) {
                setLastError(QStringLiteral("Paired, but trust failed: %1").arg(reply.errorMessage()));
            } else {
                setLastError(QString());
            }
            watcher->deleteLater();
            setDeviceBusy(path, false);
            queryManagedObjects();
        });
    });
#else
    Q_UNUSED(path)
    setLastError(QStringLiteral("Bluetooth controller is available on Linux/Pi only"));
#endif
}

void BluetoothController::connectDevice(const QString &path)
{
#if defined(Q_OS_LINUX)
    if (!m_powered) {
        setLastError(QStringLiteral("Turn Bluetooth ON first"));
        return;
    }
    if (!findDevice(path)) {
        setLastError(QStringLiteral("Device not found"));
        return;
    }

    setDeviceBusy(path, true);
    callDeviceMethod(path, QStringLiteral("Connect"), {}, [this, path](bool ok) {
        setDeviceBusy(path, false);
        if (!ok) {
            return;
        }
        if (const DeviceInfo *device = findDevice(path)) {
            rememberLastConnected(device->address);
        }
        queryManagedObjects();
    });
#else
    Q_UNUSED(path)
    setLastError(QStringLiteral("Bluetooth controller is available on Linux/Pi only"));
#endif
}

void BluetoothController::disconnectDevice(const QString &path)
{
#if defined(Q_OS_LINUX)
    if (!findDevice(path)) {
        return;
    }
    setDeviceBusy(path, true);
    callDeviceMethod(path, QStringLiteral("Disconnect"), {}, [this, path](bool) {
        setDeviceBusy(path, false);
        queryManagedObjects();
    });
#else
    Q_UNUSED(path)
#endif
}

void BluetoothController::forgetDevice(const QString &path)
{
#if defined(Q_OS_LINUX)
    if (!m_adapterPresent || m_adapterPath.isEmpty()) {
        setLastError(QStringLiteral("No Bluetooth adapter found"));
        return;
    }
    if (!findDevice(path)) {
        return;
    }

    setDeviceBusy(path, true);

    QDBusInterface adapterIface(QStringLiteral("org.bluez"),
                                m_adapterPath,
                                QStringLiteral("org.bluez.Adapter1"),
                                QDBusConnection::systemBus());
    if (!adapterIface.isValid()) {
        setDeviceBusy(path, false);
        setLastError(QStringLiteral("Bluetooth adapter interface is invalid"));
        return;
    }

    QList<QVariant> arguments;
    arguments << QVariant::fromValue(QDBusObjectPath(path));

    QDBusPendingCall call = adapterIface.asyncCallWithArgumentList(QStringLiteral("RemoveDevice"), arguments);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, path]() {
        const QDBusMessage reply = watcher->reply();
        if (reply.type() == QDBusMessage::ErrorMessage) {
            setLastError(QStringLiteral("Forget device failed: %1").arg(reply.errorMessage()));
        } else {
            setLastError(QString());
        }
        watcher->deleteLater();
        setDeviceBusy(path, false);
        queryManagedObjects();
    });
#else
    Q_UNUSED(path)
#endif
}

void BluetoothController::reconnectLastDevice()
{
    if (m_lastConnectedAddress.isEmpty()) {
        return;
    }
    if (!m_supported || !m_powered) {
        return;
    }

    QString targetPath;
    for (auto it = m_deviceMap.cbegin(); it != m_deviceMap.cend(); ++it) {
        const DeviceInfo &device = it.value();
        if (device.address.compare(m_lastConnectedAddress, Qt::CaseInsensitive) == 0) {
            if (!device.connected) {
                targetPath = device.path;
            }
            break;
        }
    }

    if (!targetPath.isEmpty()) {
        connectDevice(targetPath);
    }
}

#if defined(Q_OS_LINUX)
bool BluetoothController::hasBluezService() const
{
    QDBusConnectionInterface *iface = QDBusConnection::systemBus().interface();
    if (!iface) {
        return false;
    }
    QDBusReply<bool> reply = iface->isServiceRegistered(QStringLiteral("org.bluez"));
    return reply.isValid() && reply.value();
}

void BluetoothController::subscribeBluezSignals()
{
    QDBusConnection::systemBus().connect(
        QStringLiteral("org.bluez"),
        QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesAdded"),
        this,
        SLOT(onInterfacesAdded(QDBusObjectPath,QVariantMap)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.bluez"),
        QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesRemoved"),
        this,
        SLOT(onInterfacesRemoved(QDBusObjectPath,QStringList)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.bluez"),
        QString(),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onAdapterPropertiesChanged(QString,QVariantMap,QStringList)));
}

void BluetoothController::queryManagedObjects()
{
    if (!m_supported && hasBluezService()) {
        m_supported = true;
        emit supportedChanged();
    }
    if (!m_supported) {
        return;
    }

    QDBusInterface objectManager(QStringLiteral("org.bluez"),
                                 QStringLiteral("/"),
                                 QStringLiteral("org.freedesktop.DBus.ObjectManager"),
                                 QDBusConnection::systemBus());
    if (!objectManager.isValid()) {
        if (m_supported) {
            m_supported = false;
            emit supportedChanged();
        }
        if (m_adapterPresent) {
            m_adapterPresent = false;
            emit adapterPresentChanged();
        }
        if (m_powered) {
            m_powered = false;
            emit poweredChanged();
        }
        if (m_discovering) {
            m_discovering = false;
            emit discoveringChanged();
        }
        m_deviceMap.clear();
        rebuildDeviceList();
        setLastError(QStringLiteral("BlueZ service unavailable"));
        return;
    }

    QDBusPendingCall call = objectManager.asyncCall(QStringLiteral("GetManagedObjects"));
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        const QDBusMessage reply = watcher->reply();
        watcher->deleteLater();

        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
            setLastError(QStringLiteral("Bluetooth refresh failed: %1").arg(reply.errorMessage()));
            return;
        }

        setLastError(QString());
        handleManagedObjectsReply(reply.arguments().constFirst());
    });
}

void BluetoothController::handleManagedObjectsReply(const QVariant &value)
{
    DBusManagedObjects managedObjects;
    if (value.canConvert<QDBusArgument>()) {
        const QDBusArgument argument = value.value<QDBusArgument>();
        argument >> managedObjects;
    } else {
        return;
    }

    const bool oldAdapterPresent = m_adapterPresent;
    const bool oldPowered = m_powered;
    const bool oldDiscovering = m_discovering;

    QMap<QString, DeviceInfo> nextDevices;

    QHash<QString, bool> oldConnectedByAddress;
    for (const DeviceInfo &device : std::as_const(m_deviceMap)) {
        if (!device.address.isEmpty()) {
            oldConnectedByAddress.insert(device.address.toUpper(), device.connected);
        }
    }

    m_adapterPresent = false;
    m_adapterPath.clear();
    m_powered = false;
    m_discovering = false;

    for (auto it = managedObjects.cbegin(); it != managedObjects.cend(); ++it) {
        const QString path = it.key().path();
        const DBusInterfaceMap interfaces = it.value();

        const auto adapterIt = interfaces.find(QStringLiteral("org.bluez.Adapter1"));
        if (adapterIt != interfaces.end() && !m_adapterPresent) {
            const QVariantMap props = adapterIt.value();
            m_adapterPresent = true;
            m_adapterPath = path;
            m_powered = props.value(QStringLiteral("Powered")).toBool();
            m_discovering = props.value(QStringLiteral("Discovering")).toBool();
        }

        const auto deviceIt = interfaces.find(QStringLiteral("org.bluez.Device1"));
        if (deviceIt == interfaces.end()) {
            continue;
        }

        const QVariantMap props = deviceIt.value();
        DeviceInfo info;
        info.path = path;
        info.address = props.value(QStringLiteral("Address")).toString().toUpper();

        const QString alias = props.value(QStringLiteral("Alias")).toString();
        const QString name = props.value(QStringLiteral("Name")).toString();
        info.name = !alias.isEmpty() ? alias : (!name.isEmpty() ? name : info.address);

        info.paired = props.value(QStringLiteral("Paired")).toBool();
        info.trusted = props.value(QStringLiteral("Trusted")).toBool();
        info.connected = props.value(QStringLiteral("Connected")).toBool();
        info.rssi = props.value(QStringLiteral("RSSI"), -127).toInt();
        info.busy = m_deviceMap.value(path).busy;

        const QStringList uuids = props.value(QStringLiteral("UUIDs")).toStringList();
        bool audioCapable = false;
        for (const QString &uuid : uuids) {
            if (uuidLooksAudio(uuid)) {
                audioCapable = true;
                break;
            }
        }
        if (!audioCapable) {
            const QString icon = props.value(QStringLiteral("Icon")).toString().toLower();
            audioCapable = icon.contains(QStringLiteral("phone"))
                        || icon.contains(QStringLiteral("audio"))
                        || icon.contains(QStringLiteral("headset"))
                        || icon.contains(QStringLiteral("handsfree"))
                        || icon.contains(QStringLiteral("speaker"));
        }
        info.audioCapable = audioCapable;
        info.isLastConnected = !m_lastConnectedAddress.isEmpty()
                             && info.address.compare(m_lastConnectedAddress, Qt::CaseInsensitive) == 0;

        nextDevices.insert(path, info);
    }

    if (!m_powered && m_pairMode) {
        m_pairMode = false;
        m_pairTargetPath.clear();
        emit pairModeChanged();
        unregisterAgent();
    }

    if (oldAdapterPresent != m_adapterPresent) {
        emit adapterPresentChanged();
    }
    if (oldPowered != m_powered) {
        emit poweredChanged();
    }
    if (oldDiscovering != m_discovering) {
        emit discoveringChanged();
    }

    QHash<QString, bool> newConnectedByAddress;
    for (const DeviceInfo &device : std::as_const(nextDevices)) {
        if (!device.address.isEmpty()) {
            const QString addr = device.address.toUpper();
            newConnectedByAddress.insert(addr, device.connected);
            if (device.connected) {
                rememberLastConnected(addr);
            }
        }
    }

    QStringList addresses = oldConnectedByAddress.keys();
    for (const QString &address : newConnectedByAddress.keys()) {
        if (!addresses.contains(address)) {
            addresses.push_back(address);
        }
    }

    for (const QString &address : std::as_const(addresses)) {
        const bool oldConnected = oldConnectedByAddress.value(address, false);
        const bool newConnected = newConnectedByAddress.value(address, false);
        if (oldConnected != newConnected) {
            emit deviceConnectionChanged(address, newConnected);
        }
    }

    m_deviceMap = nextDevices;
    rebuildDeviceList();
}

void BluetoothController::setAdapterProperty(const QString &name,
                                             const QVariant &value,
                                             const std::function<void(bool)> &onDone)
{
    QDBusInterface propertiesIface(QStringLiteral("org.bluez"),
                                   m_adapterPath,
                                   QStringLiteral("org.freedesktop.DBus.Properties"),
                                   QDBusConnection::systemBus());
    if (!propertiesIface.isValid()) {
        setLastError(QStringLiteral("Bluetooth adapter properties interface is invalid"));
        if (onDone) {
            onDone(false);
        }
        return;
    }

    QList<QVariant> arguments;
    arguments << QVariant::fromValue(QStringLiteral("org.bluez.Adapter1"))
              << QVariant::fromValue(name)
              << QVariant::fromValue(QDBusVariant(value));

    QDBusPendingCall call = propertiesIface.asyncCallWithArgumentList(QStringLiteral("Set"), arguments);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, name, onDone]() {
        const QDBusMessage reply = watcher->reply();
        const bool ok = reply.type() != QDBusMessage::ErrorMessage;
        if (!ok) {
            setLastError(QStringLiteral("Set adapter %1 failed: %2").arg(name, reply.errorMessage()));
        } else {
            setLastError(QString());
        }
        watcher->deleteLater();
        if (onDone) {
            onDone(ok);
        }
        queryManagedObjects();
    });
}

void BluetoothController::callDeviceMethod(const QString &path,
                                           const QString &method,
                                           const QList<QVariant> &arguments,
                                           const std::function<void(bool)> &onDone)
{
    QDBusInterface deviceIface(QStringLiteral("org.bluez"),
                               path,
                               QStringLiteral("org.bluez.Device1"),
                               QDBusConnection::systemBus());
    if (!deviceIface.isValid()) {
        setLastError(QStringLiteral("Device interface unavailable: %1").arg(path));
        if (onDone) {
            onDone(false);
        }
        return;
    }

    QDBusPendingCall call = deviceIface.asyncCallWithArgumentList(method, arguments);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, method, onDone]() {
        const QDBusMessage reply = watcher->reply();
        const bool ok = reply.type() != QDBusMessage::ErrorMessage;
        if (!ok) {
            setLastError(QStringLiteral("%1 failed: %2").arg(method, reply.errorMessage()));
        } else {
            setLastError(QString());
        }
        watcher->deleteLater();
        if (onDone) {
            onDone(ok);
        }
        queryManagedObjects();
    });
}

void BluetoothController::registerAgentIfNeeded()
{
    if (m_agentRegistered) {
        return;
    }

    if (!m_agentObject) {
        m_agentObject = new BluezPairAgent(this);
    }

    const QString agentPath = QStringLiteral("/org/ivi/BluetoothAgent");
    if (!QDBusConnection::systemBus().registerObject(agentPath, m_agentObject, QDBusConnection::ExportAllSlots)) {
        setLastError(QStringLiteral("Failed to register Bluetooth agent object"));
        return;
    }

    QDBusInterface managerIface(QStringLiteral("org.bluez"),
                                QStringLiteral("/org/bluez"),
                                QStringLiteral("org.bluez.AgentManager1"),
                                QDBusConnection::systemBus());
    if (!managerIface.isValid()) {
        QDBusConnection::systemBus().unregisterObject(agentPath);
        setLastError(QStringLiteral("BlueZ AgentManager unavailable"));
        return;
    }

    QDBusReply<void> registerReply = managerIface.call(QStringLiteral("RegisterAgent"),
                                                       QDBusObjectPath(agentPath),
                                                       QStringLiteral("NoInputNoOutput"));
    if (!registerReply.isValid()
            && registerReply.error().name() != QStringLiteral("org.bluez.Error.AlreadyExists")) {
        QDBusConnection::systemBus().unregisterObject(agentPath);
        setLastError(QStringLiteral("RegisterAgent failed: %1").arg(registerReply.error().message()));
        return;
    }

    m_agentRegistered = true;
}

void BluetoothController::unregisterAgent()
{
    if (!m_agentRegistered) {
        return;
    }

    const QString agentPath = QStringLiteral("/org/ivi/BluetoothAgent");
    QDBusInterface managerIface(QStringLiteral("org.bluez"),
                                QStringLiteral("/org/bluez"),
                                QStringLiteral("org.bluez.AgentManager1"),
                                QDBusConnection::systemBus());
    if (managerIface.isValid()) {
        managerIface.call(QStringLiteral("UnregisterAgent"), QDBusObjectPath(agentPath));
    }
    QDBusConnection::systemBus().unregisterObject(agentPath);
    m_agentRegistered = false;
}

void BluetoothController::onInterfacesAdded(const QDBusObjectPath &objectPath, const QVariantMap &interfaces)
{
    Q_UNUSED(objectPath)
    Q_UNUSED(interfaces)
    queryManagedObjects();
}

void BluetoothController::onInterfacesRemoved(const QDBusObjectPath &objectPath, const QStringList &interfaces)
{
    Q_UNUSED(objectPath)
    Q_UNUSED(interfaces)
    queryManagedObjects();
}

void BluetoothController::onAdapterPropertiesChanged(const QString &interface,
                                                     const QVariantMap &changedProps,
                                                     const QStringList &invalidated)
{
    Q_UNUSED(changedProps)
    Q_UNUSED(invalidated)
    if (interface == QStringLiteral("org.bluez.Adapter1")
            || interface == QStringLiteral("org.bluez.Device1")) {
        queryManagedObjects();
    }
}
#endif

#if defined(Q_OS_LINUX)
#include "bluetoothcontroller.moc"
#endif
