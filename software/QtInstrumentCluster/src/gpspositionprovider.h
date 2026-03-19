#ifndef GPSPOSITIONPROVIDER_H
#define GPSPOSITIONPROVIDER_H

#include <QAbstractSocket>
#include <QByteArray>
#include <QObject>
#include <QString>

class QTcpSocket;
class QTimer;
class QJsonObject;
class QJsonValue;

class GpsPositionProvider : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool hasFix READ hasFix NOTIFY hasFixChanged)
    Q_PROPERTY(double latitude READ latitude NOTIFY positionDataChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY positionDataChanged)
    Q_PROPERTY(double horizontalAccuracyMeters READ horizontalAccuracyMeters NOTIFY positionDataChanged)
    Q_PROPERTY(double speedKmh READ speedKmh NOTIFY positionDataChanged)
    Q_PROPERTY(double headingDeg READ headingDeg NOTIFY positionDataChanged)
    Q_PROPERTY(qint64 timestampMs READ timestampMs NOTIFY positionDataChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)
    Q_PROPERTY(QString sourceName READ sourceName CONSTANT)

public:
    static GpsPositionProvider *instance();

    explicit GpsPositionProvider(QObject *parent = nullptr);

    bool connected() const;
    bool hasFix() const;
    double latitude() const;
    double longitude() const;
    double horizontalAccuracyMeters() const;
    double speedKmh() const;
    double headingDeg() const;
    qint64 timestampMs() const;
    QString errorString() const;
    QString sourceName() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();

signals:
    void connectedChanged();
    void hasFixChanged();
    void positionDataChanged();
    void errorChanged();
    void positionChanged(double latitude, double longitude, double speedKmh, double headingDeg, double timestampMs);

private slots:
    void onConnected();
    void onDisconnected();
    void onReadyRead();
    void onSocketError(QAbstractSocket::SocketError socketError);
    void reconnect();

private:
    void setConnected(bool connected);
    void setHasFix(bool hasFix);
    void setErrorString(const QString &error);
    void processLine(const QByteArray &line);
    void handleGpsdObject(const QJsonObject &object);
    double parseHorizontalAccuracyMeters(const QJsonObject &object) const;
    qint64 parseTimestampMs(const QJsonValue &value) const;
    void sendWatchCommand();

    QTcpSocket *m_socket;
    QTimer *m_reconnectTimer;
    QByteArray m_buffer;
    QString m_host;
    quint16 m_port;
    int m_reconnectIntervalMs;
    bool m_running;
    bool m_connected;
    bool m_hasFix;
    double m_latitude;
    double m_longitude;
    double m_horizontalAccuracyMeters;
    double m_speedKmh;
    double m_headingDeg;
    qint64 m_timestampMs;
    QString m_errorString;
};

#endif // GPSPOSITIONPROVIDER_H
