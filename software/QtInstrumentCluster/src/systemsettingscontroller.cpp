#include "systemsettingscontroller.h"

#include <QDebug>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

#if defined(Q_OS_LINUX)
#include <QProcess>
#include <QTimer>
#include <unistd.h>   // write(), close(), lseek()
#include <fcntl.h>     // open(), O_WRONLY
#endif

namespace {
QString resolveExecutableCandidate(const QString &value, const QString &baseDir = QString())
{
    const QString trimmed = value.trimmed();
    if (trimmed.isEmpty())
        return QString();

    const QFileInfo directInfo(trimmed);
    if (directInfo.isAbsolute()) {
        if (directInfo.exists() && directInfo.isExecutable())
            return directInfo.absoluteFilePath();
        return QString();
    }

    if (trimmed.contains(QLatin1Char('/'))) {
        const QDir dir(baseDir.isEmpty() ? QDir::currentPath() : baseDir);
        const QString candidate = dir.absoluteFilePath(trimmed);
        const QFileInfo candidateInfo(candidate);
        if (candidateInfo.exists() && candidateInfo.isExecutable())
            return candidateInfo.absoluteFilePath();
        return QString();
    }

    return QStandardPaths::findExecutable(trimmed);
}

bool isVirtualEnvPython(const QString &pythonPath)
{
    const QFileInfo pythonInfo(pythonPath);
    if (!pythonInfo.exists() || !pythonInfo.isExecutable())
        return false;

    QDir binDir = pythonInfo.absoluteDir();
    if (binDir.dirName() != QLatin1String("bin"))
        return false;

    if (!binDir.cdUp())
        return false;

    return QFileInfo(binDir.absoluteFilePath(QStringLiteral("pyvenv.cfg"))).exists();
}
}

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
    m_maxBrightness = readMaxBrightness();

    qDebug() << "[SystemSettings] audio backend :" << m_audioBackend;
    qDebug() << "[SystemSettings] wifi  backend :" << m_wifiBackend;
    qDebug() << "[SystemSettings] backlight path:" << m_backlightPath
             << " max:" << m_maxBrightness;

    // Open persistent fd for brightness sysfs (zero-latency writes)
    openBrightnessFd();

    // ── Throttle timers ──
    // Volume: gom nhiều thay đổi slider lại, chỉ gọi pactl/amixer 1 lần sau 50 ms
    m_volumeThrottle = new QTimer(this);
    m_volumeThrottle->setSingleShot(true);
    m_volumeThrottle->setInterval(50);
    connect(m_volumeThrottle, &QTimer::timeout, this, [this]() {
        if (m_pendingVolume >= 0.0) {
            applyVolumeToSystem(m_pendingVolume);
            m_pendingVolume = -1.0;
        }
    });

    // Brightness: ghi sysfs trực tiếp nên rất nhanh, nhưng vẫn throttle 30 ms
    // để tránh flood syscall trên Pi
    m_brightnessThrottle = new QTimer(this);
    m_brightnessThrottle->setSingleShot(true);
    m_brightnessThrottle->setInterval(30);
    connect(m_brightnessThrottle, &QTimer::timeout, this, [this]() {
        if (m_pendingBrightness >= 0.0) {
            applyBrightnessToSystem(m_pendingBrightness);
            m_pendingBrightness = -1.0;
        }
    });

    // Periodic sync timer – reads real state every 10 s (increased from 5 s)
    // syncFromSystem runs blocking QProcess calls, 10 s is gentler on Pi CPU
    m_syncTimer = new QTimer(this);
    m_syncTimer->setInterval(10000);
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
    if (m_brightnessFd >= 0)
        ::close(m_brightnessFd);
#endif
}

// ────────────────────────── Property getters ──────────────────────────

bool SystemSettingsController::wifiEnabled() const           { return m_wifiEnabled; }
bool SystemSettingsController::bluetoothEnabled() const      { return m_bluetoothEnabled; }
qreal SystemSettingsController::volumeLevel() const          { return m_volumeLevel; }
qreal SystemSettingsController::brightnessLevel() const      { return m_brightnessLevel; }
QVariantList SystemSettingsController::wifiNetworks() const  { return m_wifiNetworks; }
QString SystemSettingsController::connectedWifiSSID() const  { return m_connectedWifiSSID; }
bool SystemSettingsController::wifiConnecting() const        { return m_wifiConnecting; }
QString SystemSettingsController::wifiStatusMessage() const  { return m_wifiStatusMessage; }

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

#if defined(Q_OS_LINUX)
    // Throttle: chỉ gọi pactl/amixer sau khi slider ngừng thay đổi 50 ms
    m_pendingVolume = clamped;
    m_volumeThrottle->start();
#else
    applyVolumeToSystem(clamped);
#endif
}

void SystemSettingsController::setBrightnessLevel(qreal level)
{
    const qreal clamped = qBound<qreal>(0.0, level, 1.0);
    
    qreal snapped = 1.0;
    if (clamped <= 0.375) snapped = 0.25;
    else if (clamped <= 0.625) snapped = 0.50;
    else if (clamped <= 0.875) snapped = 0.75;
    else snapped = 1.0;

    if (qFuzzyCompare(m_brightnessLevel, snapped))
        return;

    m_brightnessLevel = snapped;
    emit brightnessLevelChanged();

#if defined(Q_OS_LINUX)
    // Throttle: ghi sysfs sau 30 ms (đủ nhanh cho cảm giác real-time)
    m_pendingBrightness = snapped;
    m_brightnessThrottle->start();
#else
    applyBrightnessToSystem(snapped);
#endif
}

// ────────────────────────── Power management ──────────────────────────

void SystemSettingsController::systemReboot()
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] REBOOT requested";
    QProcess::startDetached(QStringLiteral("sudo"), { QStringLiteral("systemctl"), QStringLiteral("reboot") });
#endif
}

void SystemSettingsController::systemShutdown()
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] SHUTDOWN requested";
    QProcess::startDetached(QStringLiteral("sudo"), { QStringLiteral("systemctl"), QStringLiteral("poweroff") });
#endif
}

void SystemSettingsController::restartApp()
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] RESTART APP requested";
    QProcess::startDetached(QStringLiteral("sudo"), { QStringLiteral("systemctl"), QStringLiteral("restart"), QStringLiteral("qt-cluster.service") });
    QCoreApplication::quit();
#endif
}

bool SystemSettingsController::launchDrowsyCamera()
{
#if defined(Q_OS_LINUX)
    const QString controlScriptPath = resolveDrowsyCameraControlScriptPath();
    if (controlScriptPath.isEmpty()) {
        qWarning() << "[SystemSettings] Cannot find Driver-Drowsy-Detection/app/drowsy_camera_ctl.py";
        return false;
    }

    const QString cameraRoot = resolveDrowsyCameraRoot(controlScriptPath);
    if (cameraRoot.isEmpty()) {
        qWarning() << "[SystemSettings] Cannot resolve Driver-Drowsy-Detection root from" << controlScriptPath;
        return false;
    }

    const QString pythonPath = resolveDrowsyCameraPython(cameraRoot);
    if (pythonPath.isEmpty()) {
        qWarning() << "[SystemSettings] Cannot find Python virtualenv for drowsy camera under" << cameraRoot
                   << "(checked DROWSY_PYTHON, .venv-pi/bin/python3, .venv/bin/python3)";
        return false;
    }

    QStringList args = buildDrowsyCameraControlArguments();
    args.prepend(controlScriptPath);

    const bool started = QProcess::startDetached(pythonPath, args, cameraRoot);
    if (!started) {
        qWarning() << "[SystemSettings] Failed to launch drowsy camera:"
                   << "python=" << pythonPath
                   << "control=" << controlScriptPath
                   << "workdir=" << cameraRoot
                   << "args=" << args;
        return false;
    }

    qInfo() << "[SystemSettings] Drowsy camera launched:"
            << "python=" << pythonPath
            << "control=" << controlScriptPath
            << "workdir=" << cameraRoot
            << "args=" << args;
    return true;
#else
    qWarning() << "[SystemSettings] launchDrowsyCamera is only supported on Linux.";
    return false;
#endif
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

            if (net[QStringLiteral("active")].toBool() && m_connectedWifiSSID != ssid) {
                m_connectedWifiSSID = ssid;
                emit connectedWifiSSIDChanged();
            }
            networks.append(net);
        }

        m_wifiNetworks = networks;
        emit wifiNetworksChanged();
        m_scanProcess->deleteLater();
        m_scanProcess = nullptr;
    });

    m_scanProcess->start(QStringLiteral("sudo"),
        { QStringLiteral("nmcli"), QStringLiteral("-t"), QStringLiteral("-f"),
          QStringLiteral("SSID,SIGNAL,SECURITY,ACTIVE"),
          QStringLiteral("dev"), QStringLiteral("wifi"), QStringLiteral("list"),
          QStringLiteral("--rescan"), QStringLiteral("yes") });
#endif
}

void SystemSettingsController::connectToWifi(const QString &ssid, const QString &password)
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] connecting to Wi-Fi:" << ssid;

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
            proc->deleteLater();
            return;
        }
        if (password.isEmpty()) {
            m_wifiConnecting = false;
            m_wifiStatusMessage.clear();
            emit wifiConnectingChanged();
            emit wifiStatusMessageChanged();
            emit wifiConnectionResult(false, QStringLiteral("NEED_PASSWORD"));
        } else {
            const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            m_wifiConnecting = false;
            m_wifiStatusMessage = err.isEmpty() ? QStringLiteral("Connection failed") : err;
            emit wifiConnectingChanged();
            emit wifiStatusMessageChanged();
            emit wifiConnectionResult(false, m_wifiStatusMessage);
        }
        proc->deleteLater();
    });

    if (password.isEmpty()) {
        proc->start(QStringLiteral("sudo"),
            { QStringLiteral("nmcli"), QStringLiteral("con"), QStringLiteral("up"), ssid });
    } else {
        proc->start(QStringLiteral("sudo"),
            { QStringLiteral("nmcli"), QStringLiteral("dev"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid,
              QStringLiteral("password"), password });
    }
#else
    Q_UNUSED(ssid); Q_UNUSED(password);
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
    proc->start(QStringLiteral("sudo"),
        { QStringLiteral("nmcli"), QStringLiteral("dev"), QStringLiteral("disconnect"), QStringLiteral("wlan0") });
#endif
}

// ────────────────────────── syncFromSystem ──────────────────────────

void SystemSettingsController::syncFromSystem()
{
#if defined(Q_OS_LINUX)
    const bool sysWifi = readSystemWifiState();
    if (m_wifiEnabled != sysWifi) {
        m_wifiEnabled = sysWifi;
        emit wifiEnabledChanged();
    }

    const bool sysBt = readSystemBluetoothState();
    if (m_bluetoothEnabled != sysBt) {
        m_bluetoothEnabled = sysBt;
        emit bluetoothEnabledChanged();
    }

    const qreal sysVol = readSystemVolume();
    if (sysVol >= 0.0 && !qFuzzyCompare(m_volumeLevel, sysVol)) {
        m_volumeLevel = sysVol;
        emit volumeLevelChanged();
    }

    const qreal sysBright = readSystemBrightness();
    if (sysBright >= 0.0 && !qFuzzyCompare(m_brightnessLevel, sysBright)) {
        m_brightnessLevel = sysBright;
        emit brightnessLevelChanged();
    }

    // Connected SSID
    {
        QProcess proc;
        proc.start(QStringLiteral("nmcli"), {
            QStringLiteral("-t"), QStringLiteral("-f"),
            QStringLiteral("NAME,TYPE,DEVICE"),
            QStringLiteral("con"), QStringLiteral("show"), QStringLiteral("--active")
        });
        proc.waitForFinished(2000);

        QString ssid;
        const QString output = QString::fromUtf8(proc.readAllStandardOutput());
        const QStringList lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
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
    qDebug() << "[SystemSettings] Wi-Fi:" << on;
    if (m_wifiBackend == QStringLiteral("nmcli")) {
        QProcess::startDetached(QStringLiteral("nmcli"),
            { QStringLiteral("radio"), QStringLiteral("wifi"),
              on ? QStringLiteral("on") : QStringLiteral("off") });
    } else {
        QProcess::startDetached(QStringLiteral("rfkill"),
            { on ? QStringLiteral("unblock") : QStringLiteral("block"),
              QStringLiteral("wifi") });
    }
#else
    Q_UNUSED(on);
#endif
}

void SystemSettingsController::applyBluetoothToSystem(bool on)
{
#if defined(Q_OS_LINUX)
    qDebug() << "[SystemSettings] Bluetooth:" << on;
    if (on) {
        QProcess::startDetached(QStringLiteral("sudo"),
            { QStringLiteral("rfkill"), QStringLiteral("unblock"), QStringLiteral("bluetooth") });
    }
    auto *proc = new QProcess();
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            proc, &QProcess::deleteLater);
    proc->start(QStringLiteral("sudo"),
        { QStringLiteral("bluetoothctl"), QStringLiteral("power"), on ? QStringLiteral("on") : QStringLiteral("off") });
#else
    Q_UNUSED(on);
#endif
}

void SystemSettingsController::applyVolumeToSystem(qreal level)
{
#if defined(Q_OS_LINUX)
    const int percent = static_cast<int>(level * 100.0);
    if (m_audioBackend == QStringLiteral("pactl")) {
        QProcess::startDetached(QStringLiteral("pactl"),
            { QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"),
              QStringLiteral("%1%").arg(percent) });
    } else {
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
    const int value = qMax(1, static_cast<int>(level * qMax(1, m_maxBrightness)));
    QByteArray data = QByteArray::number(value) + "\n";

    // ── Safe path: QFile write (safe for sysfs) ──
    if (!m_backlightPath.isEmpty()) {
        QFile f(m_backlightPath + QStringLiteral("/brightness"));
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            f.write(data);
            f.close();
            return;
        }
        qWarning() << "[SystemSettings] sysfs write failed:" << f.errorString() << "Trying fallback...";
    }

    // ── Last resort: sudo bash ──
    const int percent = qMax(1, static_cast<int>(level * 100.0));
    if (!m_backlightPath.isEmpty()) {
        QProcess::startDetached(QStringLiteral("sh"),
            { QStringLiteral("-c"), QString::asprintf("echo %d | sudo tee %s/brightness > /dev/null", value, qPrintable(m_backlightPath)) });
    }
#else
    Q_UNUSED(level);
#endif
}

// ────────────────────────── Drowsy camera launcher helpers ──────────────────────────

QString SystemSettingsController::readEnvOrDefault(const char *key, const QString &fallback) const
{
    const QString value = qEnvironmentVariable(key).trimmed();
    return value.isEmpty() ? fallback : value;
}

QString SystemSettingsController::resolveDrowsyCameraControlScriptPath() const
{
    const QString envPath = qEnvironmentVariable("DROWSY_CAMERA_CTL_SCRIPT").trimmed();
    if (!envPath.isEmpty()) {
        const QFileInfo envInfo(envPath);
        const QString resolvedEnvPath = envInfo.isAbsolute()
                                            ? envInfo.absoluteFilePath()
                                            : QDir(QDir::currentPath()).absoluteFilePath(envPath);
        const QFileInfo resolvedInfo(resolvedEnvPath);
        if (resolvedInfo.exists() && resolvedInfo.isFile())
            return resolvedInfo.absoluteFilePath();

        qWarning() << "[SystemSettings] DROWSY_CAMERA_CTL_SCRIPT not found:" << envPath;
    }

    const QString cwd = QDir::currentPath();
    const QString appDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        QDir(cwd).absoluteFilePath(QStringLiteral("software/Driver-Drowsy-Detection/app/drowsy_camera_ctl.py")),
        QDir(cwd).absoluteFilePath(QStringLiteral("../Driver-Drowsy-Detection/app/drowsy_camera_ctl.py")),
        QDir(cwd).absoluteFilePath(QStringLiteral("../../Driver-Drowsy-Detection/app/drowsy_camera_ctl.py")),
        QDir(appDir).absoluteFilePath(QStringLiteral("../../Driver-Drowsy-Detection/app/drowsy_camera_ctl.py")),
        QDir(appDir).absoluteFilePath(QStringLiteral("../../../Driver-Drowsy-Detection/app/drowsy_camera_ctl.py")),
    };

    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.exists() && info.isFile())
            return info.absoluteFilePath();
    }

    return QString();
}

QString SystemSettingsController::resolveDrowsyCameraRoot(const QString &scriptPath) const
{
    QFileInfo info(scriptPath);
    QDir dir = info.absoluteDir();
    if (dir.dirName() == QLatin1String("app"))
        dir.cdUp();
    return dir.absolutePath();
}

QString SystemSettingsController::resolveDrowsyCameraPython(const QString &cameraRoot) const
{
    const QString envPython = qEnvironmentVariable("DROWSY_PYTHON").trimmed();
    if (!envPython.isEmpty()) {
        const QString resolvedEnvPython = resolveExecutableCandidate(envPython, cameraRoot);
        if (!resolvedEnvPython.isEmpty() && isVirtualEnvPython(resolvedEnvPython))
            return resolvedEnvPython;

        if (resolvedEnvPython.isEmpty()) {
            qWarning() << "[SystemSettings] DROWSY_PYTHON is not executable:" << envPython;
        } else {
            qWarning() << "[SystemSettings] DROWSY_PYTHON does not point to a virtualenv python:"
                       << resolvedEnvPython;
        }
    }

    const QStringList venvCandidates = {
        QDir(cameraRoot).absoluteFilePath(QStringLiteral(".venv-pi/bin/python3")),
        QDir(cameraRoot).absoluteFilePath(QStringLiteral(".venv/bin/python3")),
    };

    for (const QString &candidate : venvCandidates) {
        if (isVirtualEnvPython(candidate))
            return QFileInfo(candidate).absoluteFilePath();
    }

    return QString();
}

QStringList SystemSettingsController::buildDrowsyCameraControlArguments() const
{
    QStringList args;
    args << "status"
         << "--start-daemon-if-needed"
         << "--backend" << readEnvOrDefault("DROWSY_BACKEND", QStringLiteral("v4l2"))
         << "--width" << readEnvOrDefault("DROWSY_WIDTH", QStringLiteral("1024"))
         << "--height" << readEnvOrDefault("DROWSY_HEIGHT", QStringLiteral("600"))
         << "--fps" << readEnvOrDefault("DROWSY_FPS", QStringLiteral("30"))
         << "--viewer-width" << readEnvOrDefault("DROWSY_VIEWER_WIDTH", QStringLiteral("1024"))
         << "--viewer-height" << readEnvOrDefault("DROWSY_VIEWER_HEIGHT", QStringLiteral("600"));

    const QString socketPath = readEnvOrDefault("DROWSY_DAEMON_SOCKET");
    if (!socketPath.isEmpty())
        args << "--socket-path" << socketPath;

    const QString cameraPath = readEnvOrDefault("DROWSY_CAMERA_PATH");
    if (!cameraPath.isEmpty()) {
        args << "--camera-path" << cameraPath;
    } else {
        args << "--camera-index" << readEnvOrDefault("DROWSY_CAMERA_INDEX", QStringLiteral("0"))
             << "--fallback-scan-max" << readEnvOrDefault("DROWSY_FALLBACK_SCAN_MAX", QStringLiteral("6"));
    }

    if (readEnvOrDefault("DROWSY_NO_MIRROR") == QLatin1String("1"))
        args << "--no-mirror";
    if (readEnvOrDefault("DROWSY_VIEWER_FULLSCREEN") == QLatin1String("1"))
        args << "--viewer-fullscreen";
    const QString viewerTitle = readEnvOrDefault("DROWSY_VIEWER_TITLE");
    if (!viewerTitle.isEmpty())
        args << "--viewer-title" << viewerTitle;

    return args;
}

// ────────────────────────── Backend detection helpers ──────────────────────────

QString SystemSettingsController::detectAudioBackend() const
{
#if defined(Q_OS_LINUX)
    { QProcess p; p.start(QStringLiteral("pactl"), {QStringLiteral("info")});
      p.waitForFinished(1500);
      if (p.exitCode() == 0) return QStringLiteral("pactl"); }
    { QProcess p; p.start(QStringLiteral("amixer"), {QStringLiteral("sget"), QStringLiteral("Master")});
      p.waitForFinished(1500);
      if (p.exitCode() == 0) return QStringLiteral("amixer"); }
#endif
    return QStringLiteral("none");
}

QString SystemSettingsController::detectWifiBackend() const
{
#if defined(Q_OS_LINUX)
    { QProcess p; p.start(QStringLiteral("nmcli"), {QStringLiteral("--version")});
      p.waitForFinished(1500);
      if (p.exitCode() == 0) return QStringLiteral("nmcli"); }
    return QStringLiteral("rfkill");
#else
    return QStringLiteral("none");
#endif
}

QString SystemSettingsController::findBacklightPath() const
{
#if defined(Q_OS_LINUX)
    // Ưu tiên: rpi_backlight (official 7" touchscreen)
    for (const QString &name : { QStringLiteral("rpi_backlight"),
                                  QStringLiteral("10-0045") }) {
        const QString path = QStringLiteral("/sys/class/backlight/") + name;
        if (QDir(path).exists())
            return path;
    }
    // Scan tất cả backlight device
    QDir blDir(QStringLiteral("/sys/class/backlight"));
    const QStringList entries = blDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (!entries.isEmpty())
        return blDir.absoluteFilePath(entries.first());
#endif
    return QString();
}

int SystemSettingsController::readMaxBrightness() const
{
#if defined(Q_OS_LINUX)
    if (m_backlightPath.isEmpty())
        return -1;
    QFile f(m_backlightPath + QStringLiteral("/max_brightness"));
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        int val = QString::fromUtf8(f.readAll().trimmed()).toInt();
        f.close();
        return val > 0 ? val : -1;
    }
#endif
    return -1;
}

void SystemSettingsController::openBrightnessFd()
{
#if defined(Q_OS_LINUX)
    // Deprecated. Kept empty to avoid crashing or hanging on sysfs.
#endif
}

// ────────────────────────── Read system state helpers ──────────────────────────

qreal SystemSettingsController::readSystemVolume() const
{
#if defined(Q_OS_LINUX)
    if (m_audioBackend == QStringLiteral("pactl")) {
        QProcess proc;
        proc.start(QStringLiteral("pactl"),
            { QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@") });
        proc.waitForFinished(1500);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        static const QRegularExpression rx(QStringLiteral("(\\d+)%"));
        QRegularExpressionMatch match = rx.match(out);
        if (match.hasMatch())
            return match.captured(1).toDouble() / 100.0;
    } else if (m_audioBackend == QStringLiteral("amixer")) {
        QProcess proc;
        proc.start(QStringLiteral("amixer"), { QStringLiteral("sget"), QStringLiteral("Master") });
        proc.waitForFinished(1500);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        static const QRegularExpression rx(QStringLiteral("\\[(\\d+)%\\]"));
        QRegularExpressionMatch match = rx.match(out);
        if (match.hasMatch())
            return match.captured(1).toDouble() / 100.0;
    }
#endif
    return -1.0;
}

qreal SystemSettingsController::readSystemBrightness() const
{
#if defined(Q_OS_LINUX)
    qreal result = -1.0;
    if (!m_backlightPath.isEmpty() && m_maxBrightness > 0) {
        QFile curFile(m_backlightPath + QStringLiteral("/brightness"));
        if (curFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            int cur = QString::fromUtf8(curFile.readAll().trimmed()).toInt();
            curFile.close();
            if (cur >= 0)
                result = static_cast<qreal>(cur) / static_cast<qreal>(m_maxBrightness);
        }
    }
    
    // Fallback: brightnessctl
    if (result < 0.0) {
        QProcess proc;
        proc.start(QStringLiteral("brightnessctl"), { QStringLiteral("info") });
        proc.waitForFinished(1500);
        const QString out = QString::fromUtf8(proc.readAllStandardOutput());
        static const QRegularExpression rx(QStringLiteral("\\((\\d+)%\\)"));
        QRegularExpressionMatch match = rx.match(out);
        if (match.hasMatch())
            result = match.captured(1).toDouble() / 100.0;
    }

    if (result >= 0.0) {
        if (result <= 0.375) return 0.25;
        if (result <= 0.625) return 0.50;
        if (result <= 0.875) return 0.75;
        return 1.0;
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
        proc.waitForFinished(1500);
        return QString::fromUtf8(proc.readAllStandardOutput()).trimmed()
                   .contains(QStringLiteral("enabled"), Qt::CaseInsensitive);
    }
    { QProcess proc;
      proc.start(QStringLiteral("rfkill"), { QStringLiteral("list"), QStringLiteral("wifi") });
      proc.waitForFinished(1500);
      return !QString::fromUtf8(proc.readAllStandardOutput())
                  .contains(QStringLiteral("Soft blocked: yes"), Qt::CaseInsensitive); }
#else
    return m_wifiEnabled;
#endif
}

bool SystemSettingsController::readSystemBluetoothState() const
{
#if defined(Q_OS_LINUX)
    { QProcess proc;
      proc.start(QStringLiteral("bluetoothctl"), { QStringLiteral("show") });
      proc.waitForFinished(1500);
      const QString out = QString::fromUtf8(proc.readAllStandardOutput());
      if (out.contains(QStringLiteral("Powered: yes"), Qt::CaseInsensitive)) return true;
      if (out.contains(QStringLiteral("Powered: no"),  Qt::CaseInsensitive)) return false; }
    { QProcess proc;
      proc.start(QStringLiteral("rfkill"), { QStringLiteral("list"), QStringLiteral("bluetooth") });
      proc.waitForFinished(1500);
      return !QString::fromUtf8(proc.readAllStandardOutput())
                  .contains(QStringLiteral("Soft blocked: yes"), Qt::CaseInsensitive); }
#else
    return m_bluetoothEnabled;
#endif
}
