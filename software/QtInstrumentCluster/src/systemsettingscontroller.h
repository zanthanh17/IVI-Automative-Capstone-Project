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

public slots:
    void setWifiEnabled(bool on);
    void setBluetoothEnabled(bool on);
    void setVolumeLevel(qreal level);
    void setBrightnessLevel(qreal level);

    void scanWifiNetworks();
    void connectToWifi(const QString &ssid, const QString &password);
    void disconnectWifi();

    void syncFromSystem();

signals:
    void wifiEnabledChanged();
    void bluetoothEnabledChanged();
    void volumeLevelChanged();
    void brightnessLevelChanged();
    void wifiNetworksChanged();
    void connectedWifiSSIDChanged();
    void wifiConnectionResult(bool success, const QString &message);

private:
    void applyWifiToSystem(bool on);
    void applyBluetoothToSystem(bool on);
    void applyVolumeToSystem(qreal level);
    void applyBrightnessToSystem(qreal level);

    QString detectAudioBackend() const;
    QString detectWifiBackend() const;
    QString findBacklightPath() const;
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

    QString m_audioBackend;
    QString m_wifiBackend;
    QString m_backlightPath;

#if defined(Q_OS_LINUX)
    QProcess *m_scanProcess = nullptr;
    QTimer *m_syncTimer = nullptr;
#endif
};

#endif // SYSTEMSETTINGSCONTROLLER_H

