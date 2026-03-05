#ifndef WEATHERPROVIDER_H
#define WEATHERPROVIDER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QTimer>

class QNetworkReply;

class WeatherProvider : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString cityName READ cityName CONSTANT)
    Q_PROPERTY(QString detailText READ detailText CONSTANT)
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

signals:
    void weatherChanged();
    void loadingChanged();
    void errorChanged();

private slots:
    void onReplyFinished(QNetworkReply *reply);

private:
    explicit WeatherProvider(QObject *parent = nullptr);
    void applyWeatherCode(int weatherCode);
    void setLoading(bool loading);
    void setErrorString(const QString &error);

    QNetworkAccessManager m_networkManager;
    QTimer m_refreshTimer;

    QString m_cityName = QStringLiteral("Da Nang, Vietnam");
    QString m_detailText = QStringLiteral("Outdoor Temperature");
    int m_temperature = 0;
    QString m_conditionText = QStringLiteral("--");
    QString m_iconType = QStringLiteral("partly");
    QString m_lastUpdated;
    bool m_loading = false;
    QString m_errorString;
};

#endif // WEATHERPROVIDER_H
