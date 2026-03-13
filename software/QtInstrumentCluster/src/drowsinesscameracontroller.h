#ifndef DROWSINESSCAMERACONTROLLER_H
#define DROWSINESSCAMERACONTROLLER_H

#include <QObject>
#include <QProcess>
#include <QImage>
#include <QMutex>
#include <QDateTime>
#include <QTimer>

class QQmlImageProviderBase;

class DrowsinessCameraController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(double detectorFps READ detectorFps NOTIFY detectorFpsChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)
    Q_PROPERTY(qulonglong frameSequence READ frameSequence NOTIFY frameSequenceChanged)
    Q_PROPERTY(QString frameTransport READ frameTransport NOTIFY frameTransportChanged)
    Q_PROPERTY(QString frameFileUrl READ frameFileUrl NOTIFY frameFileUrlChanged)

public:
    static DrowsinessCameraController *instance();

    explicit DrowsinessCameraController(QObject *parent = nullptr);
    ~DrowsinessCameraController() override;

    bool running() const;
    QString statusText() const;
    double detectorFps() const;
    QString errorText() const;
    qulonglong frameSequence() const;
    QString frameTransport() const;
    QString frameFileUrl() const;
    QImage latestFrameCopy() const;
    QQmlImageProviderBase *createImageProvider();

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void setActive(bool active);

signals:
    void runningChanged();
    void statusTextChanged();
    void detectorFpsChanged();
    void errorTextChanged();
    void frameSequenceChanged();
    void frameTransportChanged();
    void frameFileUrlChanged();

private:
    void consumeLogText(QString &buffer);
    void handleStdout();
    void handleStderr();
    void handleFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void handleProcessError(QProcess::ProcessError error);
    bool parseMetricLine(const QString &line);
    void parseFramePackets();
    void pollFrameFile();
    void clearFrame();

    QString resolveScriptPath() const;
    QString resolveWorkingDir(const QString &scriptPath) const;
    QString readEnvOrDefault(const char *key, const QString &fallback) const;

    void setRunning(bool value);
    void setStatusText(const QString &value);
    void setDetectorFps(double value);
    void setErrorText(const QString &value);

    QProcess m_process;
    QTimer m_stopTimer;
    QTimer m_framePollTimer;
    bool m_keepWorkerAliveOnHide = true;
    bool m_running = false;
    bool m_activeRequested = false;
    QString m_statusText = QStringLiteral("AI detector idle");
    double m_detectorFps = 0.0;
    QString m_errorText;
    QByteArray m_framePacketBuffer;
    QString m_stderrBuffer;
    QString m_lastStderrLine;
    QString m_startSummary;
    QString m_frameTransport = QStringLiteral("stdout");
    QString m_frameFilePath;
    QDateTime m_lastFrameFileModified;
    qint64 m_lastFrameFileSize = -1;
    mutable QMutex m_frameMutex;
    QImage m_latestFrame;
    qulonglong m_frameSequence = 0;
};

#endif // DROWSINESSCAMERACONTROLLER_H
