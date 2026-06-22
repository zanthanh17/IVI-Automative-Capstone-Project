#ifndef BLUETOOTHCONTROLLER_H
#define BLUETOOTHCONTROLLER_H

#include <QObject>
#include <QList>
#include <QMap>
#include <QSettings>
#include <QStringList>
#include <QVariantList>

#include <functional>

#if defined(Q_OS_LINUX)
#include <QDBusObjectPath>
#endif

class BluetoothController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool supported READ supported NOTIFY supportedChanged)
    Q_PROPERTY(bool adapterPresent READ adapterPresent NOTIFY adapterPresentChanged)
    Q_PROPERTY(bool powered READ powered NOTIFY poweredChanged)
    Q_PROPERTY(bool discovering READ discovering NOTIFY discoveringChanged)
    Q_PROPERTY(bool pairMode READ pairMode NOTIFY pairModeChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)

public:
    static BluetoothController *instance();

    explicit BluetoothController(QObject *parent = nullptr);
    ~BluetoothController() override;

    bool supported() const;
    bool adapterPresent() const;
    bool powered() const;
    bool discovering() const;
    bool pairMode() const;
    QString lastError() const;
    QVariantList devices() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setPowered(bool on);
    Q_INVOKABLE void setPairMode(bool enabled);
    Q_INVOKABLE void startDiscovery();
    Q_INVOKABLE void stopDiscovery();
    Q_INVOKABLE void pairDevice(const QString &path);
    Q_INVOKABLE void connectDevice(const QString &path);
    Q_INVOKABLE void disconnectDevice(const QString &path);
    Q_INVOKABLE void forgetDevice(const QString &path);
    Q_INVOKABLE void reconnectLastDevice();

signals:
    void supportedChanged();
    void adapterPresentChanged();
    void poweredChanged();
    void discoveringChanged();
    void pairModeChanged();
    void lastErrorChanged();
    void devicesChanged();
    void deviceConnectionChanged(const QString &address, bool connected);

private:
    friend class BluezPairAgent;

    struct DeviceInfo {
        QString path;
        QString address;
        QString name;
        bool paired = false;
        bool trusted = false;
        bool connected = false;
        bool audioCapable = false;
        int rssi = -127;
        bool busy = false;
        bool isLastConnected = false;
    };

    DeviceInfo *findDevice(const QString &path);
    const DeviceInfo *findDevice(const QString &path) const;
    void setDeviceBusy(const QString &path, bool busy);
    void rebuildDeviceList();
    void setLastError(const QString &message);
    void rememberLastConnected(const QString &address);
    bool allowAgentForDevice(const QString &path) const;

#if defined(Q_OS_LINUX)
    void subscribeBluezSignals();
    void queryManagedObjects();
    void handleManagedObjectsReply(const QVariant &value);
    void setAdapterProperty(const QString &name, const QVariant &value,
                            const std::function<void(bool)> &onDone = {});
    void callDeviceMethod(const QString &path,
                          const QString &method,
                          const QList<QVariant> &arguments = {},
                          const std::function<void(bool)> &onDone = {});
    void registerAgentIfNeeded();
    void unregisterAgent();
    bool hasBluezService() const;
    // Make the head unit accept incoming connections without a manual pairing
    // step: keep the adapter pairable/discoverable and auto-trust devices.
    void applyConnectableDefaults();
    void setDeviceTrusted(const QString &path);
    void autoTrustConnectedDevices();

private slots:
    void onInterfacesAdded(const QDBusObjectPath &objectPath, const QVariantMap &interfaces);
    void onInterfacesRemoved(const QDBusObjectPath &objectPath, const QStringList &interfaces);
    void onAdapterPropertiesChanged(const QString &interface,
                                    const QVariantMap &changedProps,
                                    const QStringList &invalidated);
#endif

private:
    QSettings m_settings;
    bool m_supported = false;
    bool m_adapterPresent = false;
    bool m_powered = false;
    bool m_discovering = false;
    bool m_pairMode = false;
    QString m_lastError;
    QString m_adapterPath;
    QString m_pairTargetPath;
    QString m_lastConnectedAddress;
    QVariantList m_devices;
    QMap<QString, DeviceInfo> m_deviceMap;
#if defined(Q_OS_LINUX)
    QObject *m_agentObject = nullptr;
    bool m_agentRegistered = false;
#endif
};

#endif // BLUETOOTHCONTROLLER_H
