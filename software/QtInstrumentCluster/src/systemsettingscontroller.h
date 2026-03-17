#ifndef SYSTEMSETTINGSCONTROLLER_H
#define SYSTEMSETTINGSCONTROLLER_H

#include <QObject>
#include <QSettings>
#include <QStringList>
#include <QVariantList>

#if defined(Q_OS_LINUX)
#include <QProcess>
#include <QTimer>
#endif

class SystemSettingsController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled WRITE setBluetoothEnabled NOTIFY bluetoothEnabledChanged)
    Q_PROPERTY(qreal volumeLevel READ volumeLevel WRITE setVolumeLevel NOTIFY volumeLevelChanged)
    Q_PROPERTY(qreal brightnessLevel READ brightnessLevel WRITE setBrightnessLevel NOTIFY brightnessLevelChanged)
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiNetworksChanged)
    Q_PROPERTY(QString connectedWifiSSID READ connectedWifiSSID NOTIFY connectedWifiSSIDChanged)
    Q_PROPERTY(bool wifiConnecting READ wifiConnecting NOTIFY wifiConnectingChanged)
    Q_PROPERTY(QString wifiStatusMessage READ wifiStatusMessage NOTIFY wifiStatusMessageChanged)

public:
    static SystemSettingsController *instance();

    explicit SystemSettingsController(QObject *parent = nullptr);
    ~SystemSettingsController() override;

    bool wifiEnabled() const;
    bool bluetoothEnabled() const;
    qreal volumeLevel() const;
    qreal brightnessLevel() const;
    QVariantList wifiNetworks() const;
    QString connectedWifiSSID() const;
    bool wifiConnecting() const;
    QString wifiStatusMessage() const;
    Q_INVOKABLE bool launchDrowsyCamera();

public slots:
    void setWifiEnabled(bool on);
    void setBluetoothEnabled(bool on);
    void setVolumeLevel(qreal level);
    void setBrightnessLevel(qreal level);

    void scanWifiNetworks();
    void connectToWifi(const QString &ssid, const QString &password);
    void disconnectWifi();

    void syncFromSystem();

    // Power management
    void systemReboot();
    void systemShutdown();
    void restartApp();

signals:
    void wifiEnabledChanged();
    void bluetoothEnabledChanged();
    void volumeLevelChanged();
    void brightnessLevelChanged();
    void wifiNetworksChanged();
    void connectedWifiSSIDChanged();
    void wifiConnectingChanged();
    void wifiStatusMessageChanged();
    void wifiConnectionResult(bool success, const QString &message);

private:
    void applyWifiToSystem(bool on);
    void applyBluetoothToSystem(bool on);
    void applyVolumeToSystem(qreal level);
    void applyBrightnessToSystem(qreal level);
    QString readEnvOrDefault(const char *key, const QString &fallback = QString()) const;
    QString resolveDrowsyCameraControlScriptPath() const;
    QString resolveDrowsyCameraRoot(const QString &scriptPath) const;
    QString resolveDrowsyCameraPython(const QString &cameraRoot) const;
    QStringList buildDrowsyCameraControlArguments() const;

    QString detectAudioBackend() const;
    QString detectWifiBackend() const;
    QString findBacklightPath() const;
    int  readMaxBrightness() const;
    void openBrightnessFd();

    qreal readSystemVolume() const;
    qreal readSystemBrightness() const;
    bool readSystemWifiState() const;
    bool readSystemBluetoothState() const;

    bool m_wifiEnabled;
    bool m_bluetoothEnabled;
    qreal m_volumeLevel;
    qreal m_brightnessLevel;
    QVariantList m_wifiNetworks;
    QString m_connectedWifiSSID;
    bool m_wifiConnecting = false;
    QString m_wifiStatusMessage;

    QString m_audioBackend;
    QString m_wifiBackend;
    QString m_backlightPath;
    int m_maxBrightness = -1;       // cached max_brightness value
    int m_brightnessFd  = -1;       // persistent fd for sysfs brightness

#if defined(Q_OS_LINUX)
    QProcess *m_scanProcess = nullptr;
    QTimer *m_syncTimer = nullptr;
    QTimer *m_volumeThrottle = nullptr;   // debounce volume changes
    QTimer *m_brightnessThrottle = nullptr; // debounce brightness changes
    qreal m_pendingVolume = -1.0;
    qreal m_pendingBrightness = -1.0;
#endif
};

#endif // SYSTEMSETTINGSCONTROLLER_H
