#include "weatherprovider.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

#include <cmath>

namespace {
const char kWeatherApiUrl[] =
    "https://api.open-meteo.com/v1/forecast"
    "?latitude=16.0544"
    "&longitude=108.2022"
    "&current=temperature_2m,weather_code"
    "&timezone=Asia%2FHo_Chi_Minh";
}

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

void WeatherProvider::refresh()
{
    if (m_loading) {
        return;
    }

    setLoading(true);

    QNetworkRequest request(QUrl(QString::fromLatin1(kWeatherApiUrl)));
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
