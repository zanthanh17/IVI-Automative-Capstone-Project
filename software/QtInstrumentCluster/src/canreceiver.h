#ifndef CANRECEIVER_H
#define CANRECEIVER_H

#include <QObject>
#include <QSocketNotifier>
#include <QStringList>
#include <QTimer>

class CanReceiver : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString interfaceName READ interfaceName WRITE setInterfaceName NOTIFY interfaceNameChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(bool hardwareMode READ hardwareMode WRITE setHardwareMode NOTIFY hardwareModeChanged)

public:
    explicit CanReceiver(QObject *parent = nullptr);
    ~CanReceiver();

    QString interfaceName() const;
    void setInterfaceName(const QString &name);

    bool isConnected() const;

    bool hardwareMode() const;
    void setHardwareMode(bool enabled);

    Q_INVOKABLE bool autoConnect();
    Q_INVOKABLE void disconnect();
    Q_INVOKABLE QStringList availableInterfaces() const;

signals:
    void interfaceNameChanged();
    void connectedChanged();
    void hardwareModeChanged();

    void speedReceived(int speed);
    void rpmReceived(int rpm);
    void fuelLevelReceived(float level);
    void batteryLevelReceived(float level);
    void gearReceived(QString gear);

    void buttonEvent(QString name, bool state);
    void turnLeftChanged(bool active);
    void turnRightChanged(bool active);
    void beamChanged(bool active);
    void highBeamsChanged(bool active);
    void parkedChanged(bool active);
    void airbagChanged(bool active);
    void mediaPlayToggled();
    void mediaNextTriggered();

    void canError(QString errorMessage);

private slots:
    void onReadyRead();
    void onReconnectTimer();

private:
    void closeSocket();
    void processFrame(quint32 frameId, const QByteArray &payload);
    void processTelemetryFrame(const QByteArray &payload);
    void processButtonStateFrame(const QByteArray &payload);
    void processButtonEventFrame(const QByteArray &payload);
    void emitButtonSignal(quint8 buttonId, bool active, bool triggerMedia);
    QString buttonName(quint8 buttonId) const;

    QString m_interfaceName;
    bool m_connected;
    bool m_hardwareMode;
    int m_socketFd;
    QSocketNotifier *m_notifier;
    QTimer *m_reconnectTimer;
};

#endif // CANRECEIVER_H
