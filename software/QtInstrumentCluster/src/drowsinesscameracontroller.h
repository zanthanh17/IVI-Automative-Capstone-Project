#ifndef DROWSINESSCAMERACONTROLLER_H
#define DROWSINESSCAMERACONTROLLER_H

#include <QObject>
#include <QProcess>
#include <QImage>
#include <QMutex>

class QQmlImageProviderBase;

class DrowsinessCameraController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(double detectorFps READ detectorFps NOTIFY detectorFpsChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)
    Q_PROPERTY(qulonglong frameSequence READ frameSequence NOTIFY frameSequenceChanged)

public:
    static DrowsinessCameraController *instance();

    explicit DrowsinessCameraController(QObject *parent = nullptr);
    ~DrowsinessCameraController() override;

    bool running() const;
    QString statusText() const;
    double detectorFps() const;
    QString errorText() const;
    qulonglong frameSequence() const;
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

private:
    void handleStdout();
    void handleStderr();
    void handleFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void handleProcessError(QProcess::ProcessError error);
    bool parseMetricLine(const QString &line);
    void parseFramePackets();
    void clearFrame();

    QString resolveScriptPath() const;
    QString resolveWorkingDir(const QString &scriptPath) const;
    QString readEnvOrDefault(const char *key, const QString &fallback) const;

    void setRunning(bool value);
    void setStatusText(const QString &value);
    void setDetectorFps(double value);
    void setErrorText(const QString &value);

    QProcess m_process;
    bool m_running = false;
    bool m_activeRequested = false;
    QString m_statusText = QStringLiteral("AI detector idle");
    double m_detectorFps = 0.0;
    QString m_errorText;
    QByteArray m_framePacketBuffer;
    QString m_stderrBuffer;
    mutable QMutex m_frameMutex;
    QImage m_latestFrame;
    qulonglong m_frameSequence = 0;
};

#endif // DROWSINESSCAMERACONTROLLER_H
