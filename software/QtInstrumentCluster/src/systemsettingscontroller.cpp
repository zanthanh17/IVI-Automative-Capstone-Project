#include "systemsettingscontroller.h"

#include <QDebug>

#if defined(Q_OS_LINUX)
#include <QProcess>
#endif

SystemSettingsController *SystemSettingsController::instance()
{
    static SystemSettingsController *s_instance = nullptr;
    if (!s_instance)
        s_instance = new SystemSettingsController();
    return s_instance;
}

SystemSettingsController::SystemSettingsController(QObject *parent)
    : QObject(parent)
    , m_wifiEnabled(true)
    , m_volumeLevel(0.6)
    , m_brightnessLevel(0.7)
{
}

SystemSettingsController::~SystemSettingsController() = default;

bool SystemSettingsController::wifiEnabled() const
{
    return m_wifiEnabled;
}

qreal SystemSettingsController::volumeLevel() const
{
    return m_volumeLevel;
}

qreal SystemSettingsController::brightnessLevel() const
{
    return m_brightnessLevel;
}

void SystemSettingsController::setWifiEnabled(bool on)
{
    if (m_wifiEnabled == on)
        return;

    m_wifiEnabled = on;
    emit wifiEnabledChanged();

    applyWifiToSystem(on);
}

void SystemSettingsController::setVolumeLevel(qreal level)
{
    const qreal clamped = qBound<qreal>(0.0, level, 1.0);
    if (qFuzzyCompare(m_volumeLevel, clamped))
        return;

    m_volumeLevel = clamped;
    emit volumeLevelChanged();

    applyVolumeToSystem(clamped);
}

void SystemSettingsController::setBrightnessLevel(qreal level)
{
    const qreal clamped = qBound<qreal>(0.0, level, 1.0);
    if (qFuzzyCompare(m_brightnessLevel, clamped))
        return;

    m_brightnessLevel = clamped;
    emit brightnessLevelChanged();

    applyBrightnessToSystem(clamped);
}

void SystemSettingsController::applyWifiToSystem(bool on)
{
#if defined(Q_OS_LINUX)
    // Mặc định dùng NetworkManager (nmcli). Điều chỉnh lệnh cho phù hợp môi trường trên Pi.
    const QString cmd = on ? QStringLiteral("nmcli radio wifi on")
                           : QStringLiteral("nmcli radio wifi off");
    qDebug() << "[SystemSettings] applying Wi-Fi state:" << on << cmd;
    QProcess::startDetached(QStringLiteral("/bin/sh"), { QStringLiteral("-c"), cmd });
#else
    Q_UNUSED(on);
#endif
}

void SystemSettingsController::applyVolumeToSystem(qreal level)
{
#if defined(Q_OS_LINUX)
    // Sử dụng pactl chỉnh volume mặc định theo phần trăm.
    const int percent = static_cast<int>(level * 100.0);
    const QString cmd = QStringLiteral("pactl set-sink-volume @DEFAULT_SINK@ %1%").arg(percent);
    qDebug() << "[SystemSettings] applying volume:" << percent << cmd;
    QProcess::startDetached(QStringLiteral("/bin/sh"), { QStringLiteral("-c"), cmd });
#else
    Q_UNUSED(level);
#endif
}

void SystemSettingsController::applyBrightnessToSystem(qreal level)
{
#if defined(Q_OS_LINUX)
    // Sử dụng brightnessctl nếu có mặt; nếu không, người dùng có thể thay lệnh cho phù hợp.
    const int percent = static_cast<int>(level * 100.0);
    const QString cmd = QStringLiteral("brightnessctl set %1%").arg(percent);
    qDebug() << "[SystemSettings] applying brightness:" << percent << cmd;
    QProcess::startDetached(QStringLiteral("/bin/sh"), { QStringLiteral("-c"), cmd });
#else
    Q_UNUSED(level);
#endif
}

