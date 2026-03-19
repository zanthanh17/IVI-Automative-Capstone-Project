#include "gpspositionprovider.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QTimer>
#include <QTcpSocket>
#include <QDebug>
#include <QtGlobal>

#include <cmath>
#include <limits>

namespace {

constexpr quint16 kDefaultGpsdPort = 2947;
constexpr int kDefaultReconnectMs = 3000;

quint16 readGpsdPort()
{
    bool ok = false;
    const int value = qEnvironmentVariableIntValue("GPSD_PORT", &ok);
    if (!ok || value <= 0 || value > 65535) {
        return kDefaultGpsdPort;
    }
    return static_cast<quint16>(value);
}

int readReconnectIntervalMs()
{
    bool ok = false;
    const int value = qEnvironmentVariableIntValue("GPSD_RECONNECT_MS", &ok);
    if (!ok || value < 500) {
        return kDefaultReconnectMs;
    }
    return value;
}

double normalizeHeading(double degrees)
{
    if (!std::isfinite(degrees)) {
        return 0.0;
    }

    double normalized = std::fmod(degrees, 360.0);
    if (normalized < 0.0) {
        normalized += 360.0;
    }
    return normalized;
}

} // namespace

GpsPositionProvider *GpsPositionProvider::instance()
{
    static GpsPositionProvider s_instance;
    return &s_instance;
}

GpsPositionProvider::GpsPositionProvider(QObject *parent)
    : QObject(parent)
    , m_socket(new QTcpSocket(this))
    , m_reconnectTimer(new QTimer(this))
    , m_host(qEnvironmentVariable("GPSD_HOST", "127.0.0.1"))
    , m_port(readGpsdPort())
    , m_reconnectIntervalMs(readReconnectIntervalMs())
    , m_running(false)
    , m_connected(false)
    , m_hasFix(false)
    , m_latitude(0.0)
    , m_longitude(0.0)
    , m_speedKmh(0.0)
    , m_headingDeg(0.0)
    , m_timestampMs(0)
{
    m_reconnectTimer->setInterval(m_reconnectIntervalMs);
    m_reconnectTimer->setSingleShot(true);

    connect(m_socket, &QTcpSocket::connected,
            this, &GpsPositionProvider::onConnected);
    connect(m_socket, &QTcpSocket::disconnected,
            this, &GpsPositionProvider::onDisconnected);
    connect(m_socket, &QTcpSocket::readyRead,
            this, &GpsPositionProvider::onReadyRead);
    connect(m_socket,
            QOverload<QAbstractSocket::SocketError>::of(&QTcpSocket::errorOccurred),
            this,
            &GpsPositionProvider::onSocketError);
    connect(m_reconnectTimer, &QTimer::timeout,
            this, &GpsPositionProvider::reconnect);
}

bool GpsPositionProvider::connected() const
{
    return m_connected;
}

bool GpsPositionProvider::hasFix() const
{
    return m_hasFix;
}

double GpsPositionProvider::latitude() const
{
    return m_latitude;
}

double GpsPositionProvider::longitude() const
{
    return m_longitude;
}

double GpsPositionProvider::speedKmh() const
{
    return m_speedKmh;
}

double GpsPositionProvider::headingDeg() const
{
    return m_headingDeg;
}

qint64 GpsPositionProvider::timestampMs() const
{
    return m_timestampMs;
}

QString GpsPositionProvider::errorString() const
{
    return m_errorString;
}

QString GpsPositionProvider::sourceName() const
{
    return QStringLiteral("gpsd");
}

void GpsPositionProvider::start()
{
    if (m_running) {
        return;
    }

    m_running = true;
    reconnect();
}

void GpsPositionProvider::stop()
{
    m_running = false;
    m_reconnectTimer->stop();
    m_buffer.clear();
    if (m_socket->state() != QAbstractSocket::UnconnectedState) {
        m_socket->abort();
    }
    setConnected(false);
    setHasFix(false);
}

void GpsPositionProvider::onConnected()
{
    qInfo() << "[GpsPositionProvider] Connected to gpsd at" << m_host << ":" << m_port;
    setConnected(true);
    setErrorString(QString());
    sendWatchCommand();
}

void GpsPositionProvider::onDisconnected()
{
    setConnected(false);
    setHasFix(false);

    if (m_running) {
        qInfo() << "[GpsPositionProvider] gpsd disconnected, retrying in" << m_reconnectIntervalMs << "ms";
        m_reconnectTimer->start();
    }
}

void GpsPositionProvider::onReadyRead()
{
    m_buffer.append(m_socket->readAll());

    while (m_buffer.contains('\n')) {
        const int newlineIndex = m_buffer.indexOf('\n');
        const QByteArray line = m_buffer.left(newlineIndex).trimmed();
        m_buffer.remove(0, newlineIndex + 1);

        if (!line.isEmpty()) {
            processLine(line);
        }
    }

    if (m_buffer.size() > 8192) {
        m_buffer.clear();
    }
}

void GpsPositionProvider::onSocketError(QAbstractSocket::SocketError socketError)
{
    if (socketError == QAbstractSocket::RemoteHostClosedError) {
        return;
    }

    setErrorString(m_socket->errorString());
    qWarning() << "[GpsPositionProvider] gpsd error:" << m_socket->errorString();

    if (m_running && m_socket->state() == QAbstractSocket::UnconnectedState) {
        m_reconnectTimer->start();
    }
}

void GpsPositionProvider::reconnect()
{
    if (!m_running) {
        return;
    }

    if (m_socket->state() == QAbstractSocket::ConnectedState
            || m_socket->state() == QAbstractSocket::ConnectingState) {
        return;
    }

    m_buffer.clear();
    qInfo() << "[GpsPositionProvider] Connecting to gpsd at" << m_host << ":" << m_port;
    m_socket->connectToHost(m_host, m_port);
}

void GpsPositionProvider::setConnected(bool connected)
{
    if (m_connected == connected) {
        return;
    }

    m_connected = connected;
    emit connectedChanged();
}

void GpsPositionProvider::setHasFix(bool hasFix)
{
    if (m_hasFix == hasFix) {
        return;
    }

    m_hasFix = hasFix;
    emit hasFixChanged();
}

void GpsPositionProvider::setErrorString(const QString &error)
{
    if (m_errorString == error) {
        return;
    }

    m_errorString = error;
    emit errorChanged();
}

void GpsPositionProvider::processLine(const QByteArray &line)
{
    if (line.isEmpty()) {
        return;
    }

    const char firstChar = line.at(0);
    if (firstChar != '{' && firstChar != '[') {
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        return;
    }

    if (document.isObject()) {
        handleGpsdObject(document.object());
        return;
    }

    if (!document.isArray()) {
        return;
    }

    const QJsonArray array = document.array();
    for (const QJsonValue &value : array) {
        if (value.isObject()) {
            handleGpsdObject(value.toObject());
        }
    }
}

void GpsPositionProvider::handleGpsdObject(const QJsonObject &object)
{
    if (object.value(QStringLiteral("class")).toString() != QStringLiteral("TPV")) {
        return;
    }

    const int mode = object.value(QStringLiteral("mode")).toInt(0);
    if (mode < 2) {
        setHasFix(false);
        return;
    }

    const double latitude = object.value(QStringLiteral("lat")).toDouble(std::numeric_limits<double>::quiet_NaN());
    const double longitude = object.value(QStringLiteral("lon")).toDouble(std::numeric_limits<double>::quiet_NaN());
    if (!std::isfinite(latitude) || !std::isfinite(longitude)) {
        setHasFix(false);
        return;
    }

    const double speedMs = object.value(QStringLiteral("speed")).toDouble(0.0);
    const double trackDeg = object.value(QStringLiteral("track")).toDouble(std::numeric_limits<double>::quiet_NaN());

    m_latitude = latitude;
    m_longitude = longitude;
    m_speedKmh = std::isfinite(speedMs) ? qMax(0.0, speedMs * 3.6) : 0.0;
    m_headingDeg = normalizeHeading(trackDeg);
    m_timestampMs = parseTimestampMs(object.value(QStringLiteral("time")));

    setHasFix(true);
    setErrorString(QString());
    emit positionDataChanged();
    emit positionChanged(m_latitude, m_longitude, m_speedKmh, m_headingDeg, static_cast<double>(m_timestampMs));
}

qint64 GpsPositionProvider::parseTimestampMs(const QJsonValue &value) const
{
    const QString text = value.toString().trimmed();
    if (text.isEmpty()) {
        return QDateTime::currentMSecsSinceEpoch();
    }

    QDateTime parsed = QDateTime::fromString(text, Qt::ISODateWithMs);
    if (!parsed.isValid()) {
        parsed = QDateTime::fromString(text, Qt::ISODate);
    }

    if (!parsed.isValid()) {
        return QDateTime::currentMSecsSinceEpoch();
    }

    return parsed.toMSecsSinceEpoch();
}

void GpsPositionProvider::sendWatchCommand()
{
    static const QByteArray watchCommand("?WATCH={\"enable\":true,\"json\":true};\n");
    m_socket->write(watchCommand);
    m_socket->flush();
}
