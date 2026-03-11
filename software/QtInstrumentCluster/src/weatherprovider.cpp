#include "weatherprovider.h"

#include <QDateTime>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QtGlobal>

#include <cmath>

WeatherProvider *WeatherProvider::instance()
{
    static WeatherProvider s_instance;
    return &s_instance;
}

WeatherProvider::WeatherProvider(QObject *parent)
    : QObject(parent)
{
    bool latOk = false;
    bool lonOk = false;
    const QString latEnv = qEnvironmentVariable("WEATHER_LATITUDE");
    const QString lonEnv = qEnvironmentVariable("WEATHER_LONGITUDE");
    m_latitude = latEnv.toDouble(&latOk);
    m_longitude = lonEnv.toDouble(&lonOk);
    if (!latOk || !lonOk) {
        m_latitude = std::numeric_limits<double>::quiet_NaN();
        m_longitude = std::numeric_limits<double>::quiet_NaN();
    }

    const QString cityEnv = qEnvironmentVariable("WEATHER_CITY");
    if (!cityEnv.trimmed().isEmpty()) {
        m_cityName = cityEnv.trimmed();
    }

    connect(&m_networkManager, &QNetworkAccessManager::finished,
            this, &WeatherProvider::onReplyFinished);

    m_refreshTimer.setInterval(10 * 60 * 1000);
    connect(&m_refreshTimer, &QTimer::timeout,
            this, &WeatherProvider::refresh);
    m_refreshTimer.start();

    refresh();
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

void WeatherProvider::refresh()
{
    if (m_loading) {
        return;
    }

    if (!hasConfiguredLocation()) {
        setErrorString(QStringLiteral("Missing WEATHER_LATITUDE/WEATHER_LONGITUDE"));
        return;
    }

    setLoading(true);

    QUrl url(QStringLiteral("https://api.open-meteo.com/v1/forecast"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("latitude"), QString::number(m_latitude, 'f', 6));
    query.addQueryItem(QStringLiteral("longitude"), QString::number(m_longitude, 'f', 6));
    query.addQueryItem(QStringLiteral("current"), QStringLiteral("temperature_2m,weather_code"));
    query.addQueryItem(QStringLiteral("timezone"), QStringLiteral("auto"));
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("QtInstrumentCluster/1.0"));
    request.setTransferTimeout(8000);

    m_networkManager.get(request);
}

void WeatherProvider::onReplyFinished(QNetworkReply *reply)
{
    setLoading(false);

    if (!reply) {
        setErrorString(QStringLiteral("Weather reply is null"));
        return;
    }

    const QByteArray payload = reply->readAll();
    const QNetworkReply::NetworkError networkError = reply->error();
    const QString networkErrorText = reply->errorString();
    reply->deleteLater();

    if (networkError != QNetworkReply::NoError) {
        setErrorString(networkErrorText);
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setErrorString(QStringLiteral("Invalid weather payload"));
        return;
    }

    const QJsonObject root = document.object();

    QJsonObject current = root.value(QStringLiteral("current")).toObject();
    double tempValue = current.value(QStringLiteral("temperature_2m")).toDouble(std::nan(""));
    int weatherCode = current.value(QStringLiteral("weather_code")).toInt(-1);

    if (std::isnan(tempValue) || weatherCode < 0) {
        // Backward compatibility with older Open-Meteo response format.
        current = root.value(QStringLiteral("current_weather")).toObject();
        tempValue = current.value(QStringLiteral("temperature")).toDouble(std::nan(""));
        weatherCode = current.value(QStringLiteral("weathercode")).toInt(-1);
    }

    if (std::isnan(tempValue) || weatherCode < 0) {
        setErrorString(QStringLiteral("Weather fields missing"));
        return;
    }

    m_temperature = qRound(tempValue);
    applyWeatherCode(weatherCode);
    m_lastUpdated = QDateTime::currentDateTime().toString(QStringLiteral("hh:mm"));
    setErrorString(QString());
    emit weatherChanged();
}

void WeatherProvider::applyWeatherCode(int weatherCode)
{
    if (weatherCode == 0) {
        m_conditionText = QStringLiteral("Clear Sky");
        m_iconType = QStringLiteral("sun");
        return;
    }

    if (weatherCode == 1 || weatherCode == 2) {
        m_conditionText = QStringLiteral("Partly Cloudy");
        m_iconType = QStringLiteral("partly");
        return;
    }

    if (weatherCode == 3 || weatherCode == 45 || weatherCode == 48) {
        m_conditionText = QStringLiteral("Cloudy");
        m_iconType = QStringLiteral("cloud");
        return;
    }

    if ((weatherCode >= 51 && weatherCode <= 67)
        || (weatherCode >= 80 && weatherCode <= 82)) {
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
