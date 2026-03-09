#include "systemsettingscontroller.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QTextStream>

#if defined(Q_OS_LINUX)
#include <QProcess>
#include <QTimer>
#endif

// ────────────────────────── Singleton ──────────────────────────

SystemSettingsController *SystemSettingsController::instance()
{
    static SystemSettingsController *s_instance = nullptr;
    if (!s_instance)
        s_instance = new SystemSettingsController();
    return s_instance;
}

// ────────────────────────── Ctor / Dtor ──────────────────────────

SystemSettingsController::SystemSettingsController(QObject *parent)
    : QObject(parent)
    , m_wifiEnabled(true)
    , m_bluetoothEnabled(true)
    , m_volumeLevel(0.6)
    , m_brightnessLevel(0.7)
{
#if defined(Q_OS_LINUX)
    // Detect available backends once at startup
    m_audioBackend  = detectAudioBackend();
    m_wifiBackend   = detectWifiBackend();
    m_backlightPath = findBacklightPath();

    qDebug() << "[SystemSettings] audio backend :" << m_audioBackend;
    qDebug() << "[SystemSettings] wifi  backend :" << m_wifiBackend;
    qDebug() << "[SystemSettings] backlight path:" << m_backlightPath;

    // Periodic sync timer – reads real state every 5 s so UI stays up-to-date
    // when user changes settings outside the dashboard (e.g. via terminal)
    m_syncTimer = new QTimer(this);
    m_syncTimer->setInterval(5000);
    connect(m_syncTimer, &QTimer::timeout, this, &SystemSettingsController::syncFromSystem);
    m_syncTimer->start();
#endif
}

SystemSettingsController::~SystemSettingsController()
{
#if defined(Q_OS_LINUX)
    if (m_scanProcess) {
        m_scanProcess->kill();
        m_scanProcess->waitForFinished(500);
    }
#endif
}

// ────────────────────────── Property getters ──────────────────────────

bool SystemSettingsController::wifiEnabled() const
{
    return m_wifiEnabled;
}

bool SystemSettingsController::bluetoothEnabled() const
{
    return m_bluetoothEnabled;
}

qreal SystemSettingsController::volumeLevel() const
{
    return m_volumeLevel;
}

qreal SystemSettingsController::brightnessLevel() const
{
    return m_brightnessLevel;
}

QVariantList SystemSettingsController::wifiNetworks() const
{
    return m_wifiNetworks;
}

QString SystemSettingsController::connectedWifiSSID() const
{
    return m_connectedWifiSSID;
}

bool SystemSettingsController::wifiConnecting() const
{
    return m_wifiConnecting;
}

QString SystemSettingsController::wifiStatusMessage() const
{
    return m_wifiStatusMessage;
}

// ────────────────────────── Property setters ──────────────────────────

void SystemSettingsController::setWifiEnabled(bool on)
{
    if (m_wifiEnabled == on)
        return;

    m_wifiEnabled = on;
    emit wifiEnabledChanged();

    applyWifiToSystem(on);
}

void SystemSettingsController::setBluetoothEnabled(bool on)
{
    if (m_bluetoothEnabled == on)
        return;

    m_bluetoothEnabled = on;
    emit bluetoothEnabledChanged();

    applyBluetoothToSystem(on);
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

// ────────────────────────── Wi-Fi scan / connect / disconnect ──────────────────────────

void SystemSettingsController::scanWifiNetworks()
{
#if defined(Q_OS_LINUX)
    if (m_scanProcess) {
        m_scanProcess->kill();
        m_scanProcess->waitForFinished(300);
        m_scanProcess->deleteLater();
        m_scanProcess = nullptr;
    }

    m_scanProcess = new QProcess(this);
    connect(m_scanProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int exitCode, QProcess::ExitStatus) {
        if (exitCode != 0) {
            qWarning() << "[SystemSettings] Wi-Fi scan failed";
            m_scanProcess->deleteLater();
            m_scanProcess = nullptr;
            return;
        }

        const QString output = QString::fromUtf8(m_scanProcess->readAllStandardOutput());
        QVariantList networks;

        // Parse nmcli output: SSID:SIGNAL:SECURITY:ACTIVE
        const QStringList lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            const QStringList fields = line.split(QLatin1Char(':'));
            if (fields.size() < 4)
                continue;

            const QString ssid = fields[0].trimmed();
            if (ssid.isEmpty() || ssid == QStringLiteral("--"))
                continue;

            QVariantMap net;
            net[QStringLiteral("ssid")]     = ssid;
            net[QStringLiteral("strength")] = fields[1].trimmed().toInt();
            net[QStringLiteral("secured")]  = !fields[2].trimmed().isEmpty()
                                              && fields[2].trimmed() != QStringLiteral("--");
            net[QStringLiteral("active")]   = fields[3].trimmed() == QStringLiteral("yes");

            if (net[QStringLiteral("active")].toBool()) {
                const QString newSSID = ssid;
                if (m_connectedWifiSSID != newSSID) {
                    m_connectedWifiSSID = newSSID;
                    emit connectedWifiSSIDChanged();
                }
            }

            networks.append(net);
        }

        m_wifiNetworks = networks;
        emit wifiNetworksChanged();

        m_scanProcess->deleteLater();
        m_scanProcess = nullptr;
    });

    // nmcli: terse, fields SSID,SIGNAL,SECURITY,ACTIVE
    m_scanProcess->start(QStringLiteral("nmcli"),
        { QStringLiteral("-t"), QStringLiteral("-f"),
          QStringLiteral("SSID,SIGNAL,SECURITY,ACTIVE"),
          QStringLiteral("dev"), QStringLiteral("wifi"), QStringLiteral("list"),
          QStringLiteral("--rescan"), QStringLiteral("yes") });
#endif
}

void SystemSettingsController::connectToWifi(const QString &ssid, const QString &password)
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] connecting to Wi-Fi:" << ssid;

    // --- Set connecting status ---
    m_wifiConnecting = true;
    m_wifiStatusMessage = QStringLiteral("Connecting to ") + ssid + QStringLiteral("…");
    emit wifiConnectingChanged();
    emit wifiStatusMessageChanged();

    auto *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, ssid, password](int exitCode, QProcess::ExitStatus) {
        if (exitCode == 0) {
            m_connectedWifiSSID = ssid;
            m_wifiConnecting = false;
            m_wifiStatusMessage = QStringLiteral("Connected to ") + ssid;
            emit connectedWifiSSIDChanged();
            emit wifiConnectingChanged();
            emit wifiStatusMessageChanged();
            emit wifiConnectionResult(true, m_wifiStatusMessage);
            qDebug() << "[SystemSettings] Wi-Fi connected:" << ssid;
            proc->deleteLater();
            return;
        }

        // Nếu password rỗng (thử reconnect saved) mà thất bại, không báo lỗi ngay
        // vì có thể mạng chưa lưu → QML sẽ hiện password dialog
        if (password.isEmpty()) {
            m_wifiConnecting = false;
            m_wifiStatusMessage.clear();
            emit wifiConnectingChanged();
            emit wifiStatusMessageChanged();
            // Báo cho QML biết cần nhập mật khẩu
            emit wifiConnectionResult(false, QStringLiteral("NEED_PASSWORD"));
            qDebug() << "[SystemSettings] Wi-Fi saved connection not found for:" << ssid;
        } else {
            const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            m_wifiConnecting = false;
            m_wifiStatusMessage = err.isEmpty() ? QStringLiteral("Connection failed")
                                                : err;
            emit wifiConnectingChanged();
            emit wifiStatusMessageChanged();
            emit wifiConnectionResult(false, m_wifiStatusMessage);
            qWarning() << "[SystemSettings] Wi-Fi connect failed:" << m_wifiStatusMessage;
        }
        proc->deleteLater();
    });

    if (password.isEmpty()) {
        // Thử kết nối lại bằng saved connection (nmcli con up)
        // Nếu thất bại, QML sẽ hiện dialog nhập mật khẩu
        proc->start(QStringLiteral("nmcli"),
            { QStringLiteral("con"), QStringLiteral("up"), ssid });
    } else {
        proc->start(QStringLiteral("nmcli"),
            { QStringLiteral("dev"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid,
              QStringLiteral("password"), password });
    }
#else
    Q_UNUSED(ssid);
    Q_UNUSED(password);
    emit wifiConnectionResult(false, QStringLiteral("Not supported on this platform"));
#endif
}

void SystemSettingsController::disconnectWifi()
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] disconnecting Wi-Fi";
    auto *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int, QProcess::ExitStatus) {
        m_connectedWifiSSID.clear();
        emit connectedWifiSSIDChanged();
        proc->deleteLater();
    });

    // Tìm interface wifi đang hoạt động rồi disconnect
    // Cách đơn giản: nmcli dev disconnect wlan0 (thường là wlan0 trên Pi)
    proc->start(QStringLiteral("nmcli"),
        { QStringLiteral("dev"), QStringLiteral("disconnect"), QStringLiteral("wlan0") });
#endif
}

// ────────────────────────── syncFromSystem ──────────────────────────
// Đọc trạng thái thật từ OS và cập nhật vào dashboard

void SystemSettingsController::syncFromSystem()
{
#if defined(Q_OS_LINUX)
    // --- Wi-Fi ---
    const bool sysWifi = readSystemWifiState();
    if (m_wifiEnabled != sysWifi) {
        m_wifiEnabled = sysWifi;
        emit wifiEnabledChanged();
    }

    // --- Bluetooth ---
    const bool sysBt = readSystemBluetoothState();
    if (m_bluetoothEnabled != sysBt) {
        m_bluetoothEnabled = sysBt;
        emit bluetoothEnabledChanged();
    }

    // --- Volume ---
    const qreal sysVol = readSystemVolume();
    if (sysVol >= 0.0 && !qFuzzyCompare(m_volumeLevel, sysVol)) {
        m_volumeLevel = sysVol;
        emit volumeLevelChanged();
    }

    // --- Brightness ---
    const qreal sysBright = readSystemBrightness();
    if (sysBright >= 0.0 && !qFuzzyCompare(m_brightnessLevel, sysBright)) {
        m_brightnessLevel = sysBright;
        emit brightnessLevelChanged();
    }

    // --- Connected SSID ---
    {
        QProcess proc;
        proc.start(QStringLiteral("nmcli"), {
            QStringLiteral("-t"), QStringLiteral("-f"),
            QStringLiteral("NAME,TYPE,DEVICE"),
            QStringLiteral("con"), QStringLiteral("show"), QStringLiteral("--active")
        });
        proc.waitForFinished(3000);

        QString ssid;
        const QString output = QString::fromUtf8(proc.readAllStandardOutput());
        const QStringList lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            // NAME:TYPE:DEVICE  – chỉ lấy dòng wifi
            const QStringList parts = line.split(QLatin1Char(':'));
            if (parts.size() >= 3) {
                const QString type   = parts[1].trimmed();
                const QString device = parts[2].trimmed();
                if ((type.contains(QStringLiteral("wireless")) || type.contains(QStringLiteral("wifi")))
                    && !device.isEmpty() && device != QStringLiteral("--")) {
                    ssid = parts[0].trimmed();
                    break;
                }
            }
        }

        if (m_connectedWifiSSID != ssid) {
            m_connectedWifiSSID = ssid;
            emit connectedWifiSSIDChanged();
        }
    }
#endif
}

// ────────────────────────── Apply helpers ──────────────────────────

void SystemSettingsController::applyWifiToSystem(bool on)
{
#if defined(Q_OS_LINUX)
    const QString state = on ? QStringLiteral("on") : QStringLiteral("off");
    qDebug() << "[SystemSettings] applying Wi-Fi state:" << on;

    if (m_wifiBackend == QStringLiteral("nmcli")) {
        QProcess::startDetached(QStringLiteral("nmcli"),
            { QStringLiteral("radio"), QStringLiteral("wifi"), state });
    } else {
        // rfkill fallback
        const QString action = on ? QStringLiteral("unblock") : QStringLiteral("block");
        QProcess::startDetached(QStringLiteral("rfkill"),
            { action, QStringLiteral("wifi") });
    }
#else
    Q_UNUSED(on);
#endif
}

void SystemSettingsController::applyBluetoothToSystem(bool on)
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] applying Bluetooth state:" << on;

    // Dùng bluetoothctl hoặc rfkill
    if (on) {
        QProcess::startDetached(QStringLiteral("rfkill"),
            { QStringLiteral("unblock"), QStringLiteral("bluetooth") });
        // bluetoothctl power on
        auto *proc = new QProcess();
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                proc, &QProcess::deleteLater);
        proc->start(QStringLiteral("bluetoothctl"),
            { QStringLiteral("power"), QStringLiteral("on") });
    } else {
        auto *proc = new QProcess();
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                proc, &QProcess::deleteLater);
        proc->start(QStringLiteral("bluetoothctl"),
            { QStringLiteral("power"), QStringLiteral("off") });
    }
#else
    Q_UNUSED(on);
#endif
}

void SystemSettingsController::applyVolumeToSystem(qreal level)
{
#if defined(Q_OS_LINUX)
    const int percent = static_cast<int>(level * 100.0);
    qDebug() << "[SystemSettings] applying volume:" << percent << "%";

    if (m_audioBackend == QStringLiteral("pactl")) {
        QProcess::startDetached(QStringLiteral("pactl"),
            { QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"),
              QStringLiteral("%1%").arg(percent) });
    } else if (m_audioBackend == QStringLiteral("amixer")) {
        QProcess::startDetached(QStringLiteral("amixer"),
            { QStringLiteral("sset"), QStringLiteral("Master"),
              QStringLiteral("%1%").arg(percent) });
    } else {
        // Fallback: try amixer anyway
        QProcess::startDetached(QStringLiteral("amixer"),
            { QStringLiteral("sset"), QStringLiteral("Master"),
              QStringLiteral("%1%").arg(percent) });
    }
#else
    Q_UNUSED(level);
#endif
}

void SystemSettingsController::applyBrightnessToSystem(qreal level)
{
#if defined(Q_OS_LINUX)
    const int percent = qMax(1, static_cast<int>(level * 100.0));
    qDebug() << "[SystemSettings] applying brightness:" << percent << "%";

    // Ưu tiên dùng brightnessctl (có suid bit, không cần root)
    // Nếu không có brightnessctl thì ghi trực tiếp sysfs (cần quyền)
    auto *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, level, percent](int exitCode, QProcess::ExitStatus) {
        if (exitCode != 0) {
            qWarning() << "[SystemSettings] brightnessctl failed, trying sysfs fallback";
            // Fallback: ghi trực tiếp sysfs
            if (!m_backlightPath.isEmpty()) {
                QFile maxFile(m_backlightPath + QStringLiteral("/max_brightness"));
                int maxBrightness = 255;
                if (maxFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                    maxBrightness = QString::fromUtf8(maxFile.readAll().trimmed()).toInt();
                    maxFile.close();
                }
                const int value = qMax(1, static_cast<int>(level * maxBrightness));
                QFile brightnessFile(m_backlightPath + QStringLiteral("/brightness"));
                if (brightnessFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
                    brightnessFile.write(QByteArray::number(value));
                    brightnessFile.close();
                    qDebug() << "[SystemSettings] brightness set via sysfs:" << value << "/" << maxBrightness;
                } else {
                    qWarning() << "[SystemSettings] Cannot write brightness sysfs:"
                               << brightnessFile.errorString()
                               << "Run: sudo chmod a+w" << (m_backlightPath + "/brightness")
                               << " or install brightnessctl";
                }
            } else {
                qWarning() << "[SystemSettings] No backlight path found and brightnessctl unavailable.";
            }
        } else {
            qDebug() << "[SystemSettings] brightness set via brightnessctl:" << percent << "%";
        }
        proc->deleteLater();
    });

    proc->start(QStringLiteral("brightnessctl"),
        { QStringLiteral("set"), QStringLiteral("%1%").arg(percent) });
#else
    Q_UNUSED(level);
#endif
}

// ────────────────────────── Backend detection helpers ──────────────────────────

QString SystemSettingsController::detectAudioBackend() const
{
#if defined(Q_OS_LINUX)
    // Thử pactl trước (PulseAudio / PipeWire-pulse)
    {
        QProcess proc;
        proc.start(QStringLiteral("pactl"), { QStringLiteral("info") });
        proc.waitForFinished(2000);
        if (proc.exitCode() == 0)
            return QStringLiteral("pactl");
    }
    // Nếu không, amixer (ALSA)
    {
        QProcess proc;
        proc.start(QStringLiteral("amixer"), { QStringLiteral("sget"), QStringLiteral("Master") });
        proc.waitForFinished(2000);
        if (proc.exitCode() == 0)
            return QStringLiteral("amixer");
    }
#endif
    return QStringLiteral("none");
}

QString SystemSettingsController::detectWifiBackend() const
{
#if defined(Q_OS_LINUX)
    {
        QProcess proc;
        proc.start(QStringLiteral("nmcli"), { QStringLiteral("--version") });
        proc.waitForFinished(2000);
        if (proc.exitCode() == 0)
            return QStringLiteral("nmcli");
    }
    // rfkill luôn có sẵn trên Pi
    return QStringLiteral("rfkill");
#else
    return QStringLiteral("none");
#endif
}

QString SystemSettingsController::findBacklightPath() const
{
#if defined(Q_OS_LINUX)
    // Tìm backlight device đầu tiên trong /sys/class/backlight
    QDir blDir(QStringLiteral("/sys/class/backlight"));
    const QStringList entries = blDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (!entries.isEmpty()) {
        return blDir.absoluteFilePath(entries.first());
    }
    // Fallback: Raspberry Pi official touchscreen
    const QString rpiPath = QStringLiteral("/sys/class/backlight/rpi_backlight");
    if (QDir(rpiPath).exists())
        return rpiPath;
    // Thêm fallback cho 10-inch
    const QString bl10 = QStringLiteral("/sys/class/backlight/10-0045");
    if (QDir(bl10).exists())
        return bl10;
#endif
    return QString();
}

// ────────────────────────── Read system state helpers ──────────────────────────

qreal SystemSettingsController::readSystemVolume() const
{
#if defined(Q_OS_LINUX)
    if (m_audioBackend == QStringLiteral("pactl")) {
        QProcess proc;
        proc.start(QStringLiteral("pactl"),
            { QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@") });
        proc.waitForFinished(2000);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        // Output dạng: "Volume: front-left: 42000 /  64% / ..."
        // Tìm phần trăm đầu tiên
        QRegularExpression rx(QStringLiteral("(\\d+)%"));
        QRegularExpressionMatch match = rx.match(out);
        if (match.hasMatch()) {
            return match.captured(1).toDouble() / 100.0;
        }
    } else if (m_audioBackend == QStringLiteral("amixer")) {
        QProcess proc;
        proc.start(QStringLiteral("amixer"), { QStringLiteral("sget"), QStringLiteral("Master") });
        proc.waitForFinished(2000);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        QRegularExpression rx(QStringLiteral("\\[(\\d+)%\\]"));
        QRegularExpressionMatch match = rx.match(out);
        if (match.hasMatch()) {
            return match.captured(1).toDouble() / 100.0;
        }
    }
#endif
    return -1.0; // Không đọc được
}

qreal SystemSettingsController::readSystemBrightness() const
{
#if defined(Q_OS_LINUX)
    if (!m_backlightPath.isEmpty()) {
        QFile curFile(m_backlightPath + QStringLiteral("/brightness"));
        QFile maxFile(m_backlightPath + QStringLiteral("/max_brightness"));

        int cur = -1, mx = -1;
        if (curFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            cur = QString::fromUtf8(curFile.readAll().trimmed()).toInt();
            curFile.close();
        }
        if (maxFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            mx = QString::fromUtf8(maxFile.readAll().trimmed()).toInt();
            maxFile.close();
        }

        if (cur >= 0 && mx > 0)
            return static_cast<qreal>(cur) / static_cast<qreal>(mx);
    }

    // Fallback: brightnessctl
    {
        QProcess proc;
        proc.start(QStringLiteral("brightnessctl"), { QStringLiteral("info") });
        proc.waitForFinished(2000);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        QRegularExpression rx(QStringLiteral("\\((\\d+)%\\)"));
        QRegularExpressionMatch match = rx.match(out);
        if (match.hasMatch()) {
            return match.captured(1).toDouble() / 100.0;
        }
    }
#endif
    return -1.0;
}

bool SystemSettingsController::readSystemWifiState() const
{
#if defined(Q_OS_LINUX)
    if (m_wifiBackend == QStringLiteral("nmcli")) {
        QProcess proc;
        proc.start(QStringLiteral("nmcli"), { QStringLiteral("radio"), QStringLiteral("wifi") });
        proc.waitForFinished(2000);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        return out.contains(QStringLiteral("enabled"), Qt::CaseInsensitive);
    }
    // rfkill fallback
    {
        QProcess proc;
        proc.start(QStringLiteral("rfkill"), { QStringLiteral("list"), QStringLiteral("wifi") });
        proc.waitForFinished(2000);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        // "Soft blocked: no" => wifi is enabled
        return !out.contains(QStringLiteral("Soft blocked: yes"), Qt::CaseInsensitive);
    }
#else
    return m_wifiEnabled;
#endif
}

bool SystemSettingsController::readSystemBluetoothState() const
{
#if defined(Q_OS_LINUX)
    // Dùng bluetoothctl show để kiểm tra Powered
    {
        QProcess proc;
        proc.start(QStringLiteral("bluetoothctl"), { QStringLiteral("show") });
        proc.waitForFinished(2000);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        // Tìm "Powered: yes"
        if (out.contains(QStringLiteral("Powered: yes"), Qt::CaseInsensitive))
            return true;
        if (out.contains(QStringLiteral("Powered: no"), Qt::CaseInsensitive))
            return false;
    }
    // rfkill fallback
    {
        QProcess proc;
        proc.start(QStringLiteral("rfkill"), { QStringLiteral("list"), QStringLiteral("bluetooth") });
        proc.waitForFinished(2000);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        return !out.contains(QStringLiteral("Soft blocked: yes"), Qt::CaseInsensitive);
    }
#else
    return m_bluetoothEnabled;
#endif
}

