#include "weatherprovider.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslError>
#include <QSslSocket>
#include <QStringList>
#include <QUrl>
#include <QUrlQuery>
#include <QtGlobal>

#include <cmath>

namespace {

constexpr qint64 kWeatherRefreshIntervalMs = 10 * 60 * 1000;
constexpr qint64 kMinVehicleTriggeredRefreshMs = 2 * 60 * 1000;
constexpr double kVehicleRefreshDistanceMeters = 1500.0;
constexpr double kPi = 3.14159265358979323846;
constexpr int kWeatherRequestTimeoutMs = 8000;
constexpr int kWeatherRequestTimeoutSeconds = 8;
constexpr int kCurlStartTimeoutMs = 1000;

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

bool envFlagEnabled(const char *name)
{
    const QByteArray value = qgetenv(name).trimmed().toLower();
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

QString bestProcessErrorText(const QByteArray &stderrOutput, const QString &fallback)
{
    const QString stderrText = QString::fromUtf8(stderrOutput).trimmed();
    if (!stderrText.isEmpty()) {
        return stderrText;
    }
    return fallback;
}

} // namespace

WeatherProvider *WeatherProvider::instance()
{
    static WeatherProvider s_instance;
    return &s_instance;
}

WeatherProvider::WeatherProvider(QObject *parent)
    : QObject(parent)
{
    connect(&m_networkManager, &QNetworkAccessManager::finished,
            this, &WeatherProvider::onReplyFinished);
    connect(&m_curlProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this,
            &WeatherProvider::onCurlFinished);
    connect(&m_curlProcess, &QProcess::errorOccurred,
            this, &WeatherProvider::onCurlErrorOccurred);

    m_refreshTimer.setInterval(kWeatherRefreshIntervalMs);
    connect(&m_refreshTimer, &QTimer::timeout,
            this, &WeatherProvider::refresh);
    m_refreshTimer.start();

    logSslEnvironment();
}

QString WeatherProvider::cityName() const
{
    return m_cityName;
}

QString WeatherProvider::detailText() const
{
    return m_detailText;
}

int WeatherProvider::temperature() const
{
    return m_temperature;
}

QString WeatherProvider::conditionText() const
{
    return m_conditionText;
}

QString WeatherProvider::iconType() const
{
    return m_iconType;
}

QString WeatherProvider::lastUpdated() const
{
    return m_lastUpdated;
}

bool WeatherProvider::loading() const
{
    return m_loading;
}

QString WeatherProvider::errorString() const
{
    return m_errorString;
}

bool WeatherProvider::hasConfiguredLocation() const
{
    return std::isfinite(m_latitude) && std::isfinite(m_longitude);
}

bool WeatherProvider::shouldRefreshForVehicleMove(double latitude, double longitude) const
{
    if (!std::isfinite(m_lastRequestedLatitude) || !std::isfinite(m_lastRequestedLongitude)) {
        return true;
    }

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if ((nowMs - m_lastRequestMs) < kMinVehicleTriggeredRefreshMs) {
        return false;
    }

    return haversineMeters(m_lastRequestedLatitude, m_lastRequestedLongitude,
                           latitude, longitude) >= kVehicleRefreshDistanceMeters;
}

void WeatherProvider::refresh()
{
    if (m_loading) {
        return;
    }

    if (!hasConfiguredLocation()) {
        setErrorString(QStringLiteral("Waiting for live GPS position"));
        return;
    }

    setLoading(true);
    m_lastRequestMs = QDateTime::currentMSecsSinceEpoch();
    m_lastRequestedLatitude = m_latitude;
    m_lastRequestedLongitude = m_longitude;
    requestOpenMeteo();
}

void WeatherProvider::setVehiclePosition(double latitude, double longitude)
{
    if (!std::isfinite(latitude) || !std::isfinite(longitude)) {
        return;
    }

    const bool locationChanged = !std::isfinite(m_latitude)
                                 || !std::isfinite(m_longitude)
                                 || !qFuzzyCompare(m_latitude + 1.0, latitude + 1.0)
                                 || !qFuzzyCompare(m_longitude + 1.0, longitude + 1.0);

    m_latitude = latitude;
    m_longitude = longitude;

    if (locationChanged) {
        const QString nextLabel = formattedVehicleLocationLabel();
        if (m_cityName != nextLabel) {
            m_cityName = nextLabel;
            emit weatherChanged();
        }
    }

    if (!m_loading && shouldRefreshForVehicleMove(latitude, longitude)) {
        refresh();
    }
}

QUrl WeatherProvider::buildOpenMeteoUrl() const
{
    QUrl url(QStringLiteral("https://api.open-meteo.com/v1/forecast"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("latitude"), QString::number(m_latitude, 'f', 6));
    query.addQueryItem(QStringLiteral("longitude"), QString::number(m_longitude, 'f', 6));
    query.addQueryItem(QStringLiteral("current"),
                       QStringLiteral("temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code"));
    query.addQueryItem(QStringLiteral("timezone"), QStringLiteral("auto"));
    url.setQuery(query);
    return url;
}

bool WeatherProvider::shouldUseCurlTransport() const
{
    if (envFlagEnabled("WEATHER_FORCE_CURL")) {
        return true;
    }

    return !QSslSocket::supportsSsl();
}

bool WeatherProvider::shouldRetryWithCurl(QNetworkReply *reply, const QString &networkErrorText) const
{
    if (!reply) {
        return false;
    }

    if (reply->error() == QNetworkReply::SslHandshakeFailedError) {
        return true;
    }

    const QString lowered = networkErrorText.toLower();
    return lowered.contains(QStringLiteral("ssl"))
            || lowered.contains(QStringLiteral("tls"))
            || lowered.contains(QStringLiteral("certificate"))
            || lowered.contains(QStringLiteral("handshake"));
}

void WeatherProvider::requestOpenMeteo()
{
    const QUrl url = buildOpenMeteoUrl();
    m_activeWeatherUrl = url;

    if (shouldUseCurlTransport()) {
        requestOpenMeteoViaCurl(url, QStringLiteral("Qt SSL backend unavailable"));
        return;
    }

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("QtInstrumentCluster/1.0"));
    request.setTransferTimeout(kWeatherRequestTimeoutMs);

    QNetworkReply *reply = m_networkManager.get(request);
    connect(reply, &QNetworkReply::sslErrors,
            this,
            [reply](const QList<QSslError> &errors) {
                QStringList messages;
                for (const QSslError &error : errors) {
                    messages.push_back(error.errorString());
                }
                qWarning() << "[WeatherProvider] SSL errors for" << reply->url()
                           << ":" << messages.join(QStringLiteral(" | "));
            });
}

void WeatherProvider::requestOpenMeteoViaCurl(const QUrl &url, const QString &reason)
{
    qInfo() << "[WeatherProvider] Falling back to curl for Open-Meteo:" << reason;

    if (m_curlProcess.state() != QProcess::NotRunning) {
        m_curlProcess.kill();
        m_curlProcess.waitForFinished(kCurlStartTimeoutMs);
    }

    m_usingCurlFallback = true;
    m_activeWeatherUrl = url;

    QStringList arguments;
    arguments << QStringLiteral("--fail")
              << QStringLiteral("--silent")
              << QStringLiteral("--show-error")
              << QStringLiteral("--location")
              << QStringLiteral("--max-time")
              << QString::number(kWeatherRequestTimeoutSeconds)
              << QStringLiteral("--user-agent")
              << QStringLiteral("QtInstrumentCluster/1.0")
              << url.toString();

    m_curlProcess.start(QStringLiteral("curl"), arguments);
    if (!m_curlProcess.waitForStarted(kCurlStartTimeoutMs)) {
        m_usingCurlFallback = false;
        setLoading(false);
        setErrorString(QStringLiteral("Failed to start curl for weather request"));
    }
}

void WeatherProvider::onReplyFinished(QNetworkReply *reply)
{
    if (!reply) {
        setLoading(false);
        setErrorString(QStringLiteral("Weather reply is null"));
        return;
    }

    const QByteArray payload = reply->readAll();
    const QNetworkReply::NetworkError networkError = reply->error();
    const QString networkErrorText = reply->errorString();
    const QUrl replyUrl = reply->url();
    const bool retryWithCurl = !m_usingCurlFallback && shouldRetryWithCurl(reply, networkErrorText);
    reply->deleteLater();

    if (networkError != QNetworkReply::NoError) {
        if (retryWithCurl) {
            requestOpenMeteoViaCurl(replyUrl.isValid() ? replyUrl : m_activeWeatherUrl, networkErrorText);
            return;
        }

        setLoading(false);
        setErrorString(networkErrorText);
        return;
    }

    setLoading(false);
    handleOpenMeteoReply(payload);
}

void WeatherProvider::onCurlFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    const QByteArray stdoutPayload = m_curlProcess.readAllStandardOutput();
    const QByteArray stderrPayload = m_curlProcess.readAllStandardError();

    m_usingCurlFallback = false;
    setLoading(false);

    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        setErrorString(bestProcessErrorText(stderrPayload,
                                            QStringLiteral("curl weather request failed")));
        return;
    }

    handleOpenMeteoReply(stdoutPayload);
}

void WeatherProvider::onCurlErrorOccurred(QProcess::ProcessError error)
{
    if (error == QProcess::Crashed) {
        return;
    }

    if (m_curlProcess.state() == QProcess::NotRunning) {
        m_usingCurlFallback = false;
        setLoading(false);
        setErrorString(bestProcessErrorText(m_curlProcess.readAllStandardError(),
                                            m_curlProcess.errorString()));
    }
}

void WeatherProvider::handleOpenMeteoReply(const QByteArray &payload)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setErrorString(QStringLiteral("Invalid Open-Meteo payload"));
        return;
    }

    const QJsonObject root = document.object();
    const QJsonObject current = root.value(QStringLiteral("current")).toObject();
    const double tempValue = current.value(QStringLiteral("temperature_2m")).toDouble(std::nan(""));
    const double apparentTempValue = current.value(QStringLiteral("apparent_temperature")).toDouble(std::nan(""));
    const int humidityValue = current.value(QStringLiteral("relative_humidity_2m")).toInt(-1);
    const int weatherCode = current.value(QStringLiteral("weather_code")).toInt(-1);
    const bool isDay = current.value(QStringLiteral("is_day")).toInt(1) == 1;

    if (std::isnan(tempValue) || weatherCode < 0) {
        setErrorString(QStringLiteral("Open-Meteo fields missing"));
        return;
    }

    m_cityName = formattedVehicleLocationLabel();

    m_temperature = qRound(tempValue);

    QStringList detailParts;
    if (!std::isnan(apparentTempValue)) {
        detailParts.push_back(QStringLiteral("Feels like %1°C").arg(qRound(apparentTempValue)));
    }
    if (humidityValue >= 0) {
        detailParts.push_back(QStringLiteral("Humidity %1%").arg(humidityValue));
    }
    m_detailText = detailParts.isEmpty()
                   ? QStringLiteral("Live vehicle weather")
                   : detailParts.join(QStringLiteral(" | "));

    applyWeatherCode(weatherCode, isDay);
    m_lastUpdated = QDateTime::currentDateTime().toString(QStringLiteral("hh:mm"));
    setErrorString(QString());
    emit weatherChanged();
}

void WeatherProvider::applyWeatherCode(int weatherCode, bool isDay)
{
    if (weatherCode == 0) {
        m_conditionText = QStringLiteral("Clear sky");
        m_iconType = isDay ? QStringLiteral("sun") : QStringLiteral("cloud");
        return;
    }

    if (weatherCode == 1 || weatherCode == 2) {
        m_conditionText = QStringLiteral("Partly cloudy");
        m_iconType = QStringLiteral("partly");
        return;
    }

    if (weatherCode == 3 || weatherCode == 45 || weatherCode == 48
        || (weatherCode >= 71 && weatherCode <= 77)
        || (weatherCode >= 85 && weatherCode <= 86)) {
        m_conditionText = QStringLiteral("Cloudy");
        m_iconType = QStringLiteral("cloud");
        return;
    }

    if ((weatherCode >= 51 && weatherCode <= 67) || (weatherCode >= 80 && weatherCode <= 82)) {
        m_conditionText = QStringLiteral("Rain");
        m_iconType = QStringLiteral("rain");
        return;
    }

    if (weatherCode == 95 || weatherCode == 96 || weatherCode == 99) {
        m_conditionText = QStringLiteral("Thunderstorm");
        m_iconType = QStringLiteral("storm");
        return;
    }

    m_conditionText = QStringLiteral("Cloudy");
    m_iconType = QStringLiteral("cloud");
}

QString WeatherProvider::formattedVehicleLocationLabel() const
{
    if (!hasConfiguredLocation()) {
        return QStringLiteral("Vehicle location");
    }

    return QStringLiteral("Vehicle location");
}

void WeatherProvider::logSslEnvironment()
{
    if (m_loggedSslEnvironment) {
        return;
    }

    m_loggedSslEnvironment = true;
    qInfo() << "[WeatherProvider] Source: Open-Meteo";
    qInfo() << "[WeatherProvider] Qt SSL support:" << QSslSocket::supportsSsl()
            << "build:" << QSslSocket::sslLibraryBuildVersionString()
            << "runtime:" << QSslSocket::sslLibraryVersionString()
            << "utc:" << QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
}

void WeatherProvider::setLoading(bool loading)
{
    if (m_loading == loading) {
        return;
    }

    m_loading = loading;
    emit loadingChanged();
}

void WeatherProvider::setErrorString(const QString &error)
{
    if (m_errorString == error) {
        return;
    }

    m_errorString = error;
    emit errorChanged();
}
