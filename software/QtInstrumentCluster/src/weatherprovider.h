#ifndef WEATHERPROVIDER_H
#define WEATHERPROVIDER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QTimer>
#include <limits>

class QNetworkReply;

class WeatherProvider : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString cityName READ cityName NOTIFY weatherChanged)
    Q_PROPERTY(QString detailText READ detailText NOTIFY weatherChanged)
    Q_PROPERTY(int temperature READ temperature NOTIFY weatherChanged)
    Q_PROPERTY(QString conditionText READ conditionText NOTIFY weatherChanged)
    Q_PROPERTY(QString iconType READ iconType NOTIFY weatherChanged)
    Q_PROPERTY(QString lastUpdated READ lastUpdated NOTIFY weatherChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)

public:
    static WeatherProvider *instance();

    QString cityName() const;
    QString detailText() const;
    int temperature() const;
    QString conditionText() const;
    QString iconType() const;
    QString lastUpdated() const;
    bool loading() const;
    QString errorString() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setVehiclePosition(double latitude, double longitude);

signals:
    void weatherChanged();
    void loadingChanged();
    void errorChanged();

private slots:
    void onReplyFinished(QNetworkReply *reply);

private:
    explicit WeatherProvider(QObject *parent = nullptr);
    bool hasConfiguredLocation() const;
    bool shouldRefreshForVehicleMove(double latitude, double longitude) const;
    void applyWeatherCode(int weatherCode, bool isDay);
    void requestOpenMeteo();
    void handleOpenMeteoReply(const QByteArray &payload);
    QString formattedVehicleLocationLabel() const;
    void setLoading(bool loading);
    void setErrorString(const QString &error);

    QNetworkAccessManager m_networkManager;
    QTimer m_refreshTimer;

    double m_latitude = std::numeric_limits<double>::quiet_NaN();
    double m_longitude = std::numeric_limits<double>::quiet_NaN();
    QString m_cityName = QStringLiteral("Unknown location");
    QString m_detailText = QStringLiteral("Outdoor Temperature");
    int m_temperature = 0;
    QString m_conditionText = QStringLiteral("--");
    QString m_iconType = QStringLiteral("partly");
    QString m_lastUpdated;
    bool m_loading = false;
    QString m_errorString;
    double m_lastRequestedLatitude = std::numeric_limits<double>::quiet_NaN();
    double m_lastRequestedLongitude = std::numeric_limits<double>::quiet_NaN();
    qint64 m_lastRequestMs = 0;
    bool m_hasVehiclePosition = false;
};

#endif // WEATHERPROVIDER_H
