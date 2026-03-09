#ifndef SYSTEMSETTINGSCONTROLLER_H
#define SYSTEMSETTINGSCONTROLLER_H

#include <QObject>

class SystemSettingsController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(qreal volumeLevel READ volumeLevel WRITE setVolumeLevel NOTIFY volumeLevelChanged)
    Q_PROPERTY(qreal brightnessLevel READ brightnessLevel WRITE setBrightnessLevel NOTIFY brightnessLevelChanged)

public:
    static SystemSettingsController *instance();

    explicit SystemSettingsController(QObject *parent = nullptr);
    ~SystemSettingsController() override;

    bool wifiEnabled() const;
    qreal volumeLevel() const;
    qreal brightnessLevel() const;

public slots:
    void setWifiEnabled(bool on);
    void setVolumeLevel(qreal level);      // 0.0 – 1.0
    void setBrightnessLevel(qreal level);  // 0.0 – 1.0

signals:
    void wifiEnabledChanged();
    void volumeLevelChanged();
    void brightnessLevelChanged();

private:
    void applyWifiToSystem(bool on);
    void applyVolumeToSystem(qreal level);
    void applyBrightnessToSystem(qreal level);

    bool m_wifiEnabled;
    qreal m_volumeLevel;
    qreal m_brightnessLevel;
};

#endif // SYSTEMSETTINGSCONTROLLER_H

