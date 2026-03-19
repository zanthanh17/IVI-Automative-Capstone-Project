#include "mapboxmapmatcher.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStringList>
#include <QUrl>
#include <QUrlQuery>
#include <QtGlobal>

#include <cmath>
#include <limits>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kMinRadiusMeters = 5.0;
constexpr double kDefaultRadiusMeters = 10.0;
constexpr double kMaxRadiusMeters = 30.0;

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

bool envFlagEnabled(const char *name, bool defaultValue)
{
    const QByteArray rawValue = qgetenv(name).trimmed().toLower();
    if (rawValue.isEmpty()) {
        return defaultValue;
    }

    if (rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on") {
        return true;
    }

    if (rawValue == "0" || rawValue == "false" || rawValue == "no" || rawValue == "off") {
        return false;
    }

    return defaultValue;
}

QString apiMessageFromPayload(const QByteArray &payload)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        return QString();
    }

    const QJsonObject root = document.object();
    const QString message = root.value(QStringLiteral("message")).toString().trimmed();
    if (!message.isEmpty()) {
        return message;
    }

    return root.value(QStringLiteral("error")).toString().trimmed();
}

} // namespace

MapboxMapMatcher *MapboxMapMatcher::instance()
{
    static MapboxMapMatcher s_instance;
    return &s_instance;
}

MapboxMapMatcher::MapboxMapMatcher(QObject *parent)
    : QObject(parent)
{
    connect(&m_networkManager, &QNetworkAccessManager::finished,
            this, &MapboxMapMatcher::onReplyFinished);

    bool intervalOk = false;
    const int configuredRequestInterval = qEnvironmentVariableIntValue("MAPBOX_MATCHING_MIN_INTERVAL_MS", &intervalOk);
    if (intervalOk) {
        m_minRequestIntervalMs = qBound(1000, configuredRequestInterval, 15000);
    }

    bool sampleIntervalOk = false;
    const int configuredSampleInterval = qEnvironmentVariableIntValue("MAPBOX_MATCHING_SAMPLE_MS", &sampleIntervalOk);
    if (sampleIntervalOk) {
        m_minSampleIntervalMs = qBound(500, configuredSampleInterval, 10000);
    }

    bool pointCountOk = false;
    const int configuredPointCount = qEnvironmentVariableIntValue("MAPBOX_MATCHING_TRACE_POINTS", &pointCountOk);
    if (pointCountOk) {
        m_maxTracePoints = qBound(2, configuredPointCount, 10);
    }
}

QString MapboxMapMatcher::baseUrl() const
{
    return m_baseUrl;
}

void MapboxMapMatcher::setBaseUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (trimmed.isEmpty() || m_baseUrl == trimmed) {
        return;
    }

    m_baseUrl = trimmed;
    emit baseUrlChanged();
}

QString MapboxMapMatcher::accessToken() const
{
    return m_accessToken;
}

void MapboxMapMatcher::setAccessToken(const QString &token)
{
    const bool wasEnabled = enabled();
    const QString trimmed = token.trimmed();
    if (m_accessToken == trimmed) {
        return;
    }

    m_accessToken = trimmed;
    emit accessTokenChanged();
    if (wasEnabled != enabled()) {
        emit enabledChanged();
    }

    if (!enabled()) {
        reset();
    }
}

QString MapboxMapMatcher::profile() const
{
    return m_profile;
}

void MapboxMapMatcher::setProfile(const QString &profile)
{
    const QString trimmed = profile.trimmed();
    if (trimmed.isEmpty() || m_profile == trimmed) {
        return;
    }

    m_profile = trimmed;
    emit profileChanged();
}

bool MapboxMapMatcher::enabled() const
{
    return envEnabled() && !m_accessToken.isEmpty();
}

bool MapboxMapMatcher::busy() const
{
    return m_busy;
}

bool MapboxMapMatcher::hasMatch() const
{
    return m_hasMatch;
}

double MapboxMapMatcher::matchedLatitude() const
{
    return m_matchedLatitude;
}

double MapboxMapMatcher::matchedLongitude() const
{
    return m_matchedLongitude;
}

double MapboxMapMatcher::confidence() const
{
    return m_confidence;
}

QString MapboxMapMatcher::errorString() const
{
    return m_errorString;
}

void MapboxMapMatcher::submitTracePoint(double latitude,
                                        double longitude,
                                        double speedKmh,
                                        double headingDeg,
                                        double timestampMs,
                                        double horizontalAccuracyMeters)
{
    Q_UNUSED(speedKmh)
    Q_UNUSED(headingDeg)

    if (!enabled()) {
        return;
    }

    if (!std::isfinite(latitude) || !std::isfinite(longitude)) {
        return;
    }

    const qint64 normalizedTimestampMs = timestampMs > 0.0
                                         ? qRound64(timestampMs)
                                         : QDateTime::currentMSecsSinceEpoch();
    const double radiusMeters = std::isfinite(horizontalAccuracyMeters)
                                ? qBound(kMinRadiusMeters, horizontalAccuracyMeters, kMaxRadiusMeters)
                                : kDefaultRadiusMeters;

    const TraceSample sample{ latitude, longitude, normalizedTimestampMs, radiusMeters };

    if (!m_samples.isEmpty()) {
        TraceSample &lastSample = m_samples.last();
        const double distanceMeters = haversineMeters(lastSample.latitude, lastSample.longitude,
                                                      sample.latitude, sample.longitude);
        const qint64 deltaMs = qAbs(sample.timestampMs - lastSample.timestampMs);

        if (distanceMeters < m_minSampleDistanceMeters && deltaMs < m_minSampleIntervalMs) {
            lastSample = sample;
        } else {
            m_samples.append(sample);
        }
    } else {
        m_samples.append(sample);
    }

    while (m_samples.size() > m_maxTracePoints) {
        m_samples.removeFirst();
    }

    if (m_samples.size() < 2 || m_busy) {
        return;
    }

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if ((nowMs - m_lastRequestMs) < m_minRequestIntervalMs) {
        return;
    }

    QUrl requestUrl = buildRequestUrl();
    if (!requestUrl.isValid()) {
        return;
    }

    QNetworkRequest request(requestUrl);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("QtInstrumentCluster/1.0"));
    request.setTransferTimeout(5000);

    setErrorString(QString());
    m_reply = m_networkManager.get(request);
    m_lastRequestMs = nowMs;
    setBusy(true);
}

void MapboxMapMatcher::reset()
{
    abortReply();
    m_samples.clear();
    clearMatch();
    setErrorString(QString());
}

void MapboxMapMatcher::onReplyFinished(QNetworkReply *reply)
{
    if (!reply || reply != m_reply) {
        if (reply) {
            reply->deleteLater();
        }
        return;
    }

    m_reply = nullptr;
    setBusy(false);

    const QByteArray payload = reply->readAll();
    const QNetworkReply::NetworkError networkError = reply->error();
    const QString networkErrorText = reply->errorString();
    reply->deleteLater();

    if (networkError == QNetworkReply::OperationCanceledError) {
        return;
    }

    if (networkError != QNetworkReply::NoError) {
        QString message = apiMessageFromPayload(payload);
        if (message.isEmpty()) {
            message = networkErrorText;
        }
        setErrorString(message);
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setErrorString(QStringLiteral("Invalid Mapbox map matching response"));
        return;
    }

    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("code")).toString() != QStringLiteral("Ok")) {
        QString message = root.value(QStringLiteral("message")).toString().trimmed();
        if (message.isEmpty()) {
            message = QStringLiteral("Mapbox map matching failed");
        }
        setErrorString(message);
        return;
    }

    const QJsonArray tracepoints = root.value(QStringLiteral("tracepoints")).toArray();
    QJsonObject lastTracepoint;
    for (const QJsonValue &value : tracepoints) {
        if (value.isObject()) {
            lastTracepoint = value.toObject();
        }
    }

    if (lastTracepoint.isEmpty()) {
        setErrorString(QStringLiteral("Mapbox map matching returned no tracepoint"));
        return;
    }

    const QJsonArray location = lastTracepoint.value(QStringLiteral("location")).toArray();
    if (location.size() < 2) {
        setErrorString(QStringLiteral("Mapbox map matching tracepoint is missing coordinates"));
        return;
    }

    const double matchedLongitude = location.at(0).toDouble(std::numeric_limits<double>::quiet_NaN());
    const double matchedLatitude = location.at(1).toDouble(std::numeric_limits<double>::quiet_NaN());
    if (!std::isfinite(matchedLatitude) || !std::isfinite(matchedLongitude)) {
        setErrorString(QStringLiteral("Mapbox map matching returned invalid coordinates"));
        return;
    }

    double confidence = 0.0;
    const QJsonArray matchings = root.value(QStringLiteral("matchings")).toArray();
    if (!matchings.isEmpty()) {
        confidence = qBound(0.0,
                            matchings.last().toObject().value(QStringLiteral("confidence")).toDouble(0.0),
                            1.0);
    }

    updateMatch(matchedLatitude, matchedLongitude, confidence);
    setErrorString(QString());
}

bool MapboxMapMatcher::envEnabled() const
{
    return envFlagEnabled("MAPBOX_MATCHING_ENABLED", true);
}

void MapboxMapMatcher::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }

    m_busy = busy;
    emit busyChanged();
}

void MapboxMapMatcher::setErrorString(const QString &error)
{
    if (m_errorString == error) {
        return;
    }

    m_errorString = error;
    emit errorChanged();
}

void MapboxMapMatcher::clearMatch()
{
    if (!m_hasMatch
            && qFuzzyIsNull(m_matchedLatitude)
            && qFuzzyIsNull(m_matchedLongitude)
            && qFuzzyIsNull(m_confidence)) {
        return;
    }

    m_hasMatch = false;
    m_matchedLatitude = 0.0;
    m_matchedLongitude = 0.0;
    m_confidence = 0.0;
    emit matchChanged();
}

void MapboxMapMatcher::updateMatch(double latitude, double longitude, double confidence)
{
    const bool changed = !m_hasMatch
                         || !qFuzzyCompare(m_matchedLatitude + 1.0, latitude + 1.0)
                         || !qFuzzyCompare(m_matchedLongitude + 1.0, longitude + 1.0)
                         || !qFuzzyCompare(m_confidence + 1.0, confidence + 1.0);

    m_hasMatch = true;
    m_matchedLatitude = latitude;
    m_matchedLongitude = longitude;
    m_confidence = confidence;

    if (changed) {
        emit matchChanged();
    }
}

void MapboxMapMatcher::abortReply()
{
    if (!m_reply) {
        return;
    }

    if (m_reply->isRunning()) {
        m_reply->abort();
    }
    m_reply.clear();
    setBusy(false);
}

QUrl MapboxMapMatcher::buildRequestUrl() const
{
    if (m_samples.size() < 2) {
        return QUrl();
    }

    QStringList coordinates;
    QStringList timestamps;
    QStringList radiuses;
    coordinates.reserve(m_samples.size());
    timestamps.reserve(m_samples.size());
    radiuses.reserve(m_samples.size());

    for (const TraceSample &sample : m_samples) {
        coordinates.push_back(QStringLiteral("%1,%2")
                                  .arg(sample.longitude, 0, 'f', 6)
                                  .arg(sample.latitude, 0, 'f', 6));
        timestamps.push_back(QString::number(sample.timestampMs / 1000));
        radiuses.push_back(QString::number(sample.radiusMeters, 'f', 1));
    }

    QUrl url(m_baseUrl + QStringLiteral("/matching/v5/") + m_profile
             + QStringLiteral("/") + coordinates.join(QStringLiteral(";"))
             + QStringLiteral(".json"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("geometries"), QStringLiteral("geojson"));
    query.addQueryItem(QStringLiteral("overview"), QStringLiteral("full"));
    query.addQueryItem(QStringLiteral("steps"), QStringLiteral("false"));
    query.addQueryItem(QStringLiteral("tidy"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("timestamps"), timestamps.join(QStringLiteral(";")));
    query.addQueryItem(QStringLiteral("radiuses"), radiuses.join(QStringLiteral(";")));
    query.addQueryItem(QStringLiteral("access_token"), m_accessToken);
    url.setQuery(query);
    return url;
}
