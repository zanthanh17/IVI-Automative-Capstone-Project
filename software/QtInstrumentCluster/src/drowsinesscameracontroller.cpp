#include "drowsinesscameracontroller.h"

#include <QCoreApplication>
#include <QColor>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QMutexLocker>
#include <QProcessEnvironment>
#include <QQuickImageProvider>
#include <QRegularExpression>
#include <QStandardPaths>
#include <cstring>

namespace {
constexpr char kFrameMagic[] = "FRAM";
constexpr int kFrameHeaderSize = 8;
constexpr quint32 kMaxJpegPayloadBytes = 8 * 1024 * 1024;

bool envFlagEnabled(const char *key, bool fallback)
{
    const QString value = qEnvironmentVariable(key).trimmed().toLower();
    if (value.isEmpty())
        return fallback;
    return value != QLatin1String("0")
        && value != QLatin1String("false")
        && value != QLatin1String("no")
        && value != QLatin1String("off");
}

quint32 readLeUInt32(const char *ptr)
{
    const uchar *u = reinterpret_cast<const uchar *>(ptr);
    return quint32(u[0]) | (quint32(u[1]) << 8) | (quint32(u[2]) << 16) | (quint32(u[3]) << 24);
}

class DrowsinessFrameProvider final : public QQuickImageProvider
{
public:
    explicit DrowsinessFrameProvider(DrowsinessCameraController *controller)
        : QQuickImageProvider(QQuickImageProvider::Image)
        , m_controller(controller)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        Q_UNUSED(id);
        Q_UNUSED(requestedSize);

        QImage frame = m_controller->latestFrameCopy();
        if (frame.isNull()) {
            frame = QImage(16, 16, QImage::Format_RGB32);
            frame.fill(QColor(0, 0, 0));
        }

        if (size)
            *size = frame.size();
        return frame;
    }

private:
    DrowsinessCameraController *m_controller = nullptr;
};
}

DrowsinessCameraController *DrowsinessCameraController::instance()
{
    static DrowsinessCameraController *s_instance = nullptr;
    if (!s_instance)
        s_instance = new DrowsinessCameraController();
    return s_instance;
}

DrowsinessCameraController::DrowsinessCameraController(QObject *parent)
    : QObject(parent)
{
    m_keepWorkerAliveOnHide = envFlagEnabled("DROWSY_PERSIST_WORKER", true);
    m_stopTimer.setSingleShot(true);
    m_stopTimer.setInterval(1000);
    m_framePollTimer.setInterval(80);

    connect(&m_process, &QProcess::readyReadStandardOutput,
            this, &DrowsinessCameraController::handleStdout);
    connect(&m_process, &QProcess::readyReadStandardError,
            this, &DrowsinessCameraController::handleStderr);
    connect(&m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &DrowsinessCameraController::handleFinished);
    connect(&m_process, &QProcess::errorOccurred,
            this, &DrowsinessCameraController::handleProcessError);
    connect(&m_stopTimer, &QTimer::timeout, this, [this]() {
        if (!m_activeRequested)
            stop();
    });
    connect(&m_framePollTimer, &QTimer::timeout,
            this, &DrowsinessCameraController::pollFrameFile);
}

DrowsinessCameraController::~DrowsinessCameraController()
{
    stop();
}

bool DrowsinessCameraController::running() const
{
    return m_running;
}

QString DrowsinessCameraController::statusText() const
{
    return m_statusText;
}

double DrowsinessCameraController::detectorFps() const
{
    return m_detectorFps;
}

QString DrowsinessCameraController::errorText() const
{
    return m_errorText;
}

qulonglong DrowsinessCameraController::frameSequence() const
{
    QMutexLocker locker(&m_frameMutex);
    return m_frameSequence;
}

QImage DrowsinessCameraController::latestFrameCopy() const
{
    QMutexLocker locker(&m_frameMutex);
    return m_latestFrame.copy();
}

QQmlImageProviderBase *DrowsinessCameraController::createImageProvider()
{
    return new DrowsinessFrameProvider(this);
}

void DrowsinessCameraController::start()
{
    m_activeRequested = true;
    if (m_process.state() != QProcess::NotRunning)
        return;

    const QString scriptPath = resolveScriptPath();
    if (scriptPath.isEmpty()) {
        setErrorText(QStringLiteral("Cannot find Driver-Drowsy-Detection/app/live_camera.py"));
        setStatusText(QStringLiteral("AI detector unavailable"));
        return;
    }

    const QString workDir = resolveWorkingDir(scriptPath);
    const QString pythonBin = readEnvOrDefault("DROWSY_PYTHON", QStringLiteral("python3"));
    QString resolvedPython = pythonBin;
    const QFileInfo pythonFi(pythonBin);
    if (pythonFi.isAbsolute()) {
        if (!pythonFi.exists() || !pythonFi.isExecutable())
            resolvedPython.clear();
    } else {
        resolvedPython = QStandardPaths::findExecutable(pythonBin);
    }

    if (resolvedPython.isEmpty()) {
        setErrorText(QStringLiteral("Python executable not found: %1").arg(pythonBin));
        setStatusText(QStringLiteral("AI detector unavailable"));
        return;
    }

    QStringList args;
    args << "-X" << "faulthandler"
         << "-u"
         << scriptPath
         << "--backend" << readEnvOrDefault("DROWSY_BACKEND", QStringLiteral("v4l2"))
         << "--width" << readEnvOrDefault("DROWSY_WIDTH", QStringLiteral("960"))
         << "--height" << readEnvOrDefault("DROWSY_HEIGHT", QStringLiteral("540"))
         << "--fps" << readEnvOrDefault("DROWSY_FPS", QStringLiteral("30"))
         << "--no-display"
         << "--export-quality" << readEnvOrDefault("DROWSY_EXPORT_QUALITY", QStringLiteral("70"))
         << "--export-every-n" << readEnvOrDefault("DROWSY_EXPORT_EVERY_N", QStringLiteral("1"))
         << "--metrics-every-n" << readEnvOrDefault("DROWSY_METRICS_EVERY_N", QStringLiteral("10"));

    const QString cameraPath = readEnvOrDefault("DROWSY_CAMERA_PATH", QString());
    if (!cameraPath.isEmpty()) {
        args << "--camera-path" << cameraPath;
    } else {
        args << "--camera-index" << readEnvOrDefault("DROWSY_CAMERA_INDEX", QStringLiteral("0"))
             << "--fallback-scan-max" << readEnvOrDefault("DROWSY_FALLBACK_SCAN_MAX", QStringLiteral("6"));
    }

    const QString transport = readEnvOrDefault("DROWSY_FRAME_TRANSPORT", QStringLiteral("stdout")).trimmed().toLower();
    m_frameTransport = (transport == QLatin1String("file"))
                           ? QStringLiteral("file")
                           : QStringLiteral("stdout");
    m_frameFilePath = readEnvOrDefault("DROWSY_EXPORT_FRAME", QStringLiteral("/tmp/drowsy_live_frame.jpg"));
    m_lastFrameFileModified = QDateTime();
    m_lastFrameFileSize = -1;

    if (m_frameTransport == QLatin1String("stdout")) {
        args << "--stream-jpeg-stdout";
    } else {
        args << "--export-frame" << m_frameFilePath;
    }

    m_framePacketBuffer.clear();
    m_stderrBuffer.clear();
    m_lastStderrLine.clear();
    clearFrame();
    setDetectorFps(0.0);
    setErrorText(QString());
    setStatusText(QStringLiteral("Starting AI detector..."));

    if (!workDir.isEmpty())
        m_process.setWorkingDirectory(workDir);

    m_startSummary = QStringLiteral("python=%1 script=%2 workdir=%3")
                         .arg(resolvedPython, scriptPath, workDir);
    qInfo() << "[DrowsyCamera] Starting worker:" << m_startSummary
            << "transport=" << m_frameTransport
            << "frameFile=" << m_frameFilePath;

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    if (!env.contains(QStringLiteral("PYTHONFAULTHANDLER")))
        env.insert(QStringLiteral("PYTHONFAULTHANDLER"), QStringLiteral("1"));
    m_process.setProcessEnvironment(env);
    m_process.setProgram(resolvedPython);
    m_process.setArguments(args);
    m_process.start();

    if (!m_process.waitForStarted(3000)) {
        setErrorText(QStringLiteral("Cannot start AI detector process: %1")
                         .arg(m_process.errorString()));
        setStatusText(QStringLiteral("AI detector failed to start"));
        setRunning(false);
        qWarning() << "[DrowsyCamera] FailedToStart" << m_startSummary
                   << "error=" << m_process.errorString();
        return;
    }

    setRunning(true);
    if (m_frameTransport == QLatin1String("file"))
        m_framePollTimer.start();
    else
        m_framePollTimer.stop();
}

void DrowsinessCameraController::stop()
{
    m_activeRequested = false;
    m_stopTimer.stop();
    m_framePollTimer.stop();

    if (m_process.state() == QProcess::NotRunning) {
        setRunning(false);
        setDetectorFps(0.0);
        setStatusText(QStringLiteral("AI detector stopped"));
        return;
    }

    m_process.terminate();
    if (!m_process.waitForFinished(1200))
        m_process.kill();

    setRunning(false);
    setDetectorFps(0.0);
    setStatusText(QStringLiteral("AI detector stopped"));
}

void DrowsinessCameraController::setActive(bool active)
{
    qInfo() << "[DrowsyCamera] setActive(" << active << ")"
            << "running=" << m_running
            << "state=" << m_process.state()
            << "keepAlive=" << m_keepWorkerAliveOnHide;

    if (active) {
        m_activeRequested = true;
        m_stopTimer.stop();
        start();
    } else {
        if (m_keepWorkerAliveOnHide && m_process.state() != QProcess::NotRunning) {
            m_activeRequested = true;
            qInfo() << "[DrowsyCamera] Page hidden; worker kept alive in background.";
            return;
        }

        m_activeRequested = false;
        if (!m_stopTimer.isActive())
            m_stopTimer.start();
    }
}

void DrowsinessCameraController::handleStdout()
{
    if (m_frameTransport != QLatin1String("stdout"))
        return;

    m_framePacketBuffer.append(m_process.readAllStandardOutput());
    parseFramePackets();
}

void DrowsinessCameraController::handleStderr()
{
    m_stderrBuffer += QString::fromUtf8(m_process.readAllStandardError());

    int newlineIndex = -1;
    while ((newlineIndex = m_stderrBuffer.indexOf(QLatin1Char('\n'))) >= 0) {
        const QString line = m_stderrBuffer.left(newlineIndex).trimmed();
        m_stderrBuffer.remove(0, newlineIndex + 1);

        if (line.isEmpty())
            continue;

        m_lastStderrLine = line;

        if (parseMetricLine(line))
            continue;

        if (line.startsWith(QStringLiteral("Live started"))) {
            setStatusText(QStringLiteral("AI detector running"));
            continue;
        }

        if (line.startsWith(QStringLiteral("Cannot open camera"))) {
            setErrorText(line);
            setStatusText(QStringLiteral("AI detector camera error"));
            continue;
        }

        if (line.startsWith(QStringLiteral("Missing dependency"))
            || line.contains(QStringLiteral("Traceback"))
            || line.contains(QStringLiteral("Exception"))
            || line.contains(QStringLiteral("Error"))
            || line.contains(QStringLiteral("Segmentation fault"), Qt::CaseInsensitive)
            || line.contains(QStringLiteral("Illegal instruction"), Qt::CaseInsensitive)) {
            setErrorText(line);
        }

        qDebug() << "[DrowsyCamera]" << line;
    }
}

void DrowsinessCameraController::handleFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    setRunning(false);
    setDetectorFps(0.0);

    if (!m_activeRequested) {
        setStatusText(QStringLiteral("AI detector stopped"));
        return;
    }

    if (exitStatus == QProcess::NormalExit && exitCode == 0) {
        setStatusText(QStringLiteral("AI detector stopped"));
        return;
    }

    if (m_errorText.isEmpty()) {
        if (!m_lastStderrLine.isEmpty())
            setErrorText(QStringLiteral("AI detector exited (%1): %2").arg(exitCode).arg(m_lastStderrLine));
        else
            setErrorText(QStringLiteral("AI detector exited unexpectedly (%1)").arg(exitCode));
    }
    setStatusText(QStringLiteral("AI detector stopped unexpectedly"));
    qWarning() << "[DrowsyCamera] Worker finished unexpectedly."
               << "exitCode=" << exitCode
               << "exitStatus=" << exitStatus
               << "lastStderr=" << m_lastStderrLine
               << m_startSummary;
}

void DrowsinessCameraController::handleProcessError(QProcess::ProcessError error)
{
    if (!m_activeRequested) {
        qInfo() << "[DrowsyCamera] Ignoring process error during requested stop:" << error
                << m_startSummary;
        return;
    }

    if (error == QProcess::FailedToStart)
        setErrorText(QStringLiteral("Failed to start python process. Check DROWSY_PYTHON."));
    else if (error == QProcess::Crashed)
        setErrorText(m_lastStderrLine.isEmpty()
                         ? QStringLiteral("AI detector process crashed")
                         : QStringLiteral("AI detector process crashed: %1").arg(m_lastStderrLine));
    else
        setErrorText(QStringLiteral("AI detector process error"));

    qWarning() << "[DrowsyCamera] Process error:" << error
               << "lastStderr=" << m_lastStderrLine
               << m_startSummary;
}

bool DrowsinessCameraController::parseMetricLine(const QString &line)
{
    if (!line.startsWith(QStringLiteral("[METRIC]")))
        return false;

    static const QRegularExpression metricRe(
        QStringLiteral(R"(fps=([0-9]+(?:\.[0-9]+)?)\s+latency_ms=([0-9]+(?:\.[0-9]+)?)\s+status=([a-zA-Z_]+)\s+alert=([01]))")
    );

    const QRegularExpressionMatch match = metricRe.match(line);
    if (!match.hasMatch())
        return true;

    const double fps = match.captured(1).toDouble();
    const double latency = match.captured(2).toDouble();
    const QString status = match.captured(3).toUpper();
    const bool alert = (match.captured(4) == QLatin1String("1"));

    setDetectorFps(fps);
    setStatusText(QStringLiteral("%1 | %2 FPS | %3 ms")
                  .arg(alert ? status + QStringLiteral(" ALERT") : status)
                  .arg(fps, 0, 'f', 1)
                  .arg(latency, 0, 'f', 1));
    return true;
}

void DrowsinessCameraController::parseFramePackets()
{
    while (true) {
        if (m_framePacketBuffer.size() < kFrameHeaderSize)
            return;

        if (std::memcmp(m_framePacketBuffer.constData(), kFrameMagic, 4) != 0) {
            const int syncIndex = m_framePacketBuffer.indexOf(kFrameMagic, 0);
            if (syncIndex < 0) {
                m_framePacketBuffer.clear();
                return;
            }
            m_framePacketBuffer.remove(0, syncIndex);
            if (m_framePacketBuffer.size() < kFrameHeaderSize)
                return;
        }

        const quint32 payloadBytes = readLeUInt32(m_framePacketBuffer.constData() + 4);
        if (payloadBytes == 0 || payloadBytes > kMaxJpegPayloadBytes) {
            m_framePacketBuffer.remove(0, 4);
            continue;
        }

        const int packetBytes = kFrameHeaderSize + int(payloadBytes);
        if (m_framePacketBuffer.size() < packetBytes)
            return;

        const QByteArray jpeg = m_framePacketBuffer.mid(kFrameHeaderSize, int(payloadBytes));
        m_framePacketBuffer.remove(0, packetBytes);

        QImage frame;
        if (!frame.loadFromData(jpeg, "JPG"))
            continue;

        bool sequenceChanged = false;
        {
            QMutexLocker locker(&m_frameMutex);
            m_latestFrame = frame.convertToFormat(QImage::Format_RGB32);
            ++m_frameSequence;
            sequenceChanged = true;
        }

        if (sequenceChanged)
            emit frameSequenceChanged();
    }
}

void DrowsinessCameraController::pollFrameFile()
{
    if (m_frameTransport != QLatin1String("file") || m_frameFilePath.isEmpty())
        return;

    const QFileInfo fi(m_frameFilePath);
    if (!fi.exists() || !fi.isFile())
        return;

    if (fi.lastModified() == m_lastFrameFileModified && fi.size() == m_lastFrameFileSize)
        return;

    QImage frame;
    if (!frame.load(fi.absoluteFilePath()))
        return;

    m_lastFrameFileModified = fi.lastModified();
    m_lastFrameFileSize = fi.size();

    bool sequenceChanged = false;
    {
        QMutexLocker locker(&m_frameMutex);
        m_latestFrame = frame.convertToFormat(QImage::Format_RGB32);
        ++m_frameSequence;
        sequenceChanged = true;
    }

    if (sequenceChanged)
        emit frameSequenceChanged();
}

void DrowsinessCameraController::clearFrame()
{
    bool changed = false;
    {
        QMutexLocker locker(&m_frameMutex);
        if (!m_latestFrame.isNull() || m_frameSequence != 0)
            changed = true;
        m_latestFrame = QImage();
        m_frameSequence = 0;
    }

    if (changed)
        emit frameSequenceChanged();
}

QString DrowsinessCameraController::resolveScriptPath() const
{
    const QString envPath = qEnvironmentVariable("DROWSY_LIVE_CAMERA_SCRIPT").trimmed();
    if (!envPath.isEmpty()) {
        const QFileInfo fi(envPath);
        if (fi.exists() && fi.isFile())
            return fi.absoluteFilePath();
    }

    const QString cwd = QDir::currentPath();
    const QString appDir = QCoreApplication::applicationDirPath();

    const QStringList candidates = {
        QDir(cwd).absoluteFilePath(QStringLiteral("../Driver-Drowsy-Detection/app/live_camera.py")),
        QDir(cwd).absoluteFilePath(QStringLiteral("../../Driver-Drowsy-Detection/app/live_camera.py")),
        QDir(cwd).absoluteFilePath(QStringLiteral("software/Driver-Drowsy-Detection/app/live_camera.py")),
        QDir(appDir).absoluteFilePath(QStringLiteral("../../Driver-Drowsy-Detection/app/live_camera.py")),
        QDir(appDir).absoluteFilePath(QStringLiteral("../../../Driver-Drowsy-Detection/app/live_camera.py")),
    };

    for (const QString &candidate : candidates) {
        const QFileInfo fi(candidate);
        if (fi.exists() && fi.isFile())
            return fi.absoluteFilePath();
    }
    return QString();
}

QString DrowsinessCameraController::resolveWorkingDir(const QString &scriptPath) const
{
    QFileInfo fi(scriptPath);
    QDir dir = fi.absoluteDir(); // .../Driver-Drowsy-Detection/app
    if (dir.dirName() == QLatin1String("app"))
        dir.cdUp();              // .../Driver-Drowsy-Detection
    return dir.absolutePath();
}

QString DrowsinessCameraController::readEnvOrDefault(const char *key, const QString &fallback) const
{
    const QString value = qEnvironmentVariable(key).trimmed();
    return value.isEmpty() ? fallback : value;
}

void DrowsinessCameraController::setRunning(bool value)
{
    if (m_running == value)
        return;
    m_running = value;
    emit runningChanged();
}

void DrowsinessCameraController::setStatusText(const QString &value)
{
    if (m_statusText == value)
        return;
    m_statusText = value;
    emit statusTextChanged();
}

void DrowsinessCameraController::setDetectorFps(double value)
{
    if (qFuzzyCompare(m_detectorFps, value))
        return;
    m_detectorFps = value;
    emit detectorFpsChanged();
}

void DrowsinessCameraController::setErrorText(const QString &value)
{
    if (m_errorText == value)
        return;
    m_errorText = value;
    emit errorTextChanged();
}
