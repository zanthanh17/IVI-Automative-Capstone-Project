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
constexpr double kPi = 3.14159265358979323846;
constexpr double kMinimumStationaryHoldMeters = 6.0;
constexpr double kStationarySpeedThresholdKmh = 2.0;
constexpr double kHeadingFreezeSpeedThresholdKmh = 5.0;
constexpr double kOutlierJumpMeters = 120.0;
constexpr double kMaximumReasonableSpeedMps = 85.0;
constexpr qint64 kMaximumFilterGapMs = 10000;

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

double toRadians(double degrees)
{
    return degrees * kPi / 180.0;
}

double haversineMeters(double lat1, double lon1, double lat2, double lon2)
{
    constexpr double kEarthRadiusMeters = 6371000.0;
    const double dLat = toRadians(lat2 - lat1);
    const double dLon = toRadians(lon2 - lon1);
    const double a = std::sin(dLat / 2.0) * std::sin(dLat / 2.0)
                     + std::cos(toRadians(lat1)) * std::cos(toRadians(lat2))
                     * std::sin(dLon / 2.0) * std::sin(dLon / 2.0);
    const double c = 2.0 * std::atan2(std::sqrt(a), std::sqrt(1.0 - a));
    return kEarthRadiusMeters * c;
}

double clamp01(double value)
{
    return qBound(0.0, value, 1.0);
}

double interpolateValue(double previousValue, double nextValue, double alpha)
{
    return previousValue + ((nextValue - previousValue) * clamp01(alpha));
}

double smoothingAlphaForFix(double speedKmh, double horizontalAccuracyMeters, double distanceMeters)
{
    double alpha = 0.35;

    if (speedKmh >= 60.0) {
        alpha = 0.80;
    } else if (speedKmh >= 30.0) {
        alpha = 0.65;
    } else if (speedKmh >= 10.0) {
        alpha = 0.50;
    } else if (speedKmh >= kStationarySpeedThresholdKmh) {
        alpha = 0.35;
    } else {
        alpha = 0.20;
    }

    if (std::isfinite(horizontalAccuracyMeters)) {
        if (horizontalAccuracyMeters >= 25.0) {
            alpha = qMin(alpha, 0.22);
        } else if (horizontalAccuracyMeters >= 15.0) {
            alpha = qMin(alpha, 0.30);
        }
    }

    if (distanceMeters >= 50.0) {
        alpha = qMax(alpha, 0.85);
    } else if (distanceMeters >= 20.0) {
        alpha = qMax(alpha, 0.70);
    } else if (distanceMeters >= 10.0) {
        alpha = qMax(alpha, 0.55);
    }

    return clamp01(alpha);
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
    , m_horizontalAccuracyMeters(std::numeric_limits<double>::quiet_NaN())
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

double GpsPositionProvider::horizontalAccuracyMeters() const
{
    return m_horizontalAccuracyMeters;
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
    const double horizontalAccuracyMeters = parseHorizontalAccuracyMeters(object);
    const double speedKmh = std::isfinite(speedMs) ? qMax(0.0, speedMs * 3.6) : 0.0;
    const qint64 timestampMs = parseTimestampMs(object.value(QStringLiteral("time")));

    double filteredLatitude = latitude;
    double filteredLongitude = longitude;
    double filteredHeadingDeg = normalizeHeading(trackDeg);

    if (m_hasFix) {
        const double distanceMeters = haversineMeters(m_latitude, m_longitude, latitude, longitude);
        const qint64 deltaMs = (m_timestampMs > 0 && timestampMs > 0) ? (timestampMs - m_timestampMs) : 0;
        const double deltaSeconds = deltaMs > 0 ? static_cast<double>(deltaMs) / 1000.0 : 0.0;
        const double holdRadiusMeters = qMax(kMinimumStationaryHoldMeters,
                                             std::isfinite(horizontalAccuracyMeters)
                                             ? horizontalAccuracyMeters
                                             : 0.0);

        if (deltaSeconds > 0.0
                && deltaMs <= kMaximumFilterGapMs
                && distanceMeters >= kOutlierJumpMeters
                && (distanceMeters / deltaSeconds) > kMaximumReasonableSpeedMps) {
            qWarning() << "[GpsPositionProvider] Ignoring outlier fix jump:" << distanceMeters
                       << "m in" << deltaSeconds << "s";
            return;
        }

        if (speedKmh <= kStationarySpeedThresholdKmh && distanceMeters <= holdRadiusMeters) {
            filteredLatitude = m_latitude;
            filteredLongitude = m_longitude;
        } else if (deltaMs > 0 && deltaMs <= kMaximumFilterGapMs) {
            const double alpha = smoothingAlphaForFix(speedKmh, horizontalAccuracyMeters, distanceMeters);
            filteredLatitude = interpolateValue(m_latitude, latitude, alpha);
            filteredLongitude = interpolateValue(m_longitude, longitude, alpha);
        }

        if (speedKmh <= kHeadingFreezeSpeedThresholdKmh) {
            filteredHeadingDeg = m_headingDeg;
        }
    }

    const bool didPositionChange = !qFuzzyCompare(m_latitude + 1.0, filteredLatitude + 1.0)
                                   || !qFuzzyCompare(m_longitude + 1.0, filteredLongitude + 1.0);
    const bool accuracyChanged = (std::isfinite(m_horizontalAccuracyMeters) != std::isfinite(horizontalAccuracyMeters))
                                 || (std::isfinite(m_horizontalAccuracyMeters)
                                     && std::isfinite(horizontalAccuracyMeters)
                                     && !qFuzzyCompare(m_horizontalAccuracyMeters + 1.0,
                                                       horizontalAccuracyMeters + 1.0));
    const bool speedChanged = !qFuzzyCompare(m_speedKmh + 1.0, speedKmh + 1.0);
    const bool headingChanged = !qFuzzyCompare(m_headingDeg + 1.0, filteredHeadingDeg + 1.0);
    const bool timestampChanged = m_timestampMs != timestampMs;

    m_latitude = filteredLatitude;
    m_longitude = filteredLongitude;
    m_horizontalAccuracyMeters = horizontalAccuracyMeters;
    m_speedKmh = speedKmh;
    m_headingDeg = filteredHeadingDeg;
    m_timestampMs = timestampMs;

    setHasFix(true);
    setErrorString(QString());
    if (didPositionChange || accuracyChanged || speedChanged || headingChanged || timestampChanged) {
        emit positionDataChanged();
        emit positionChanged(m_latitude, m_longitude, m_speedKmh, m_headingDeg, static_cast<double>(m_timestampMs));
    }
}

double GpsPositionProvider::parseHorizontalAccuracyMeters(const QJsonObject &object) const
{
    const double eph = object.value(QStringLiteral("eph")).toDouble(std::numeric_limits<double>::quiet_NaN());
    if (std::isfinite(eph) && eph >= 0.0) {
        return eph;
    }

    const double epx = object.value(QStringLiteral("epx")).toDouble(std::numeric_limits<double>::quiet_NaN());
    const double epy = object.value(QStringLiteral("epy")).toDouble(std::numeric_limits<double>::quiet_NaN());

    if (std::isfinite(epx) && std::isfinite(epy)) {
        return qMax(epx, epy);
    }
    if (std::isfinite(epx)) {
        return epx;
    }
    if (std::isfinite(epy)) {
        return epy;
    }

    return std::numeric_limits<double>::quiet_NaN();
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
