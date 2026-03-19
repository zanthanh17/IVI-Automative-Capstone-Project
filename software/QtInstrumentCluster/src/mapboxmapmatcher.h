#ifndef MAPBOXMAPMATCHER_H
#define MAPBOXMAPMATCHER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QString>
#include <QUrl>
#include <QVector>

class QNetworkReply;

class MapboxMapMatcher : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString accessToken READ accessToken WRITE setAccessToken NOTIFY accessTokenChanged)
    Q_PROPERTY(QString profile READ profile WRITE setProfile NOTIFY profileChanged)
    Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool hasMatch READ hasMatch NOTIFY matchChanged)
    Q_PROPERTY(double matchedLatitude READ matchedLatitude NOTIFY matchChanged)
    Q_PROPERTY(double matchedLongitude READ matchedLongitude NOTIFY matchChanged)
    Q_PROPERTY(double confidence READ confidence NOTIFY matchChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)

public:
    static MapboxMapMatcher *instance();

    explicit MapboxMapMatcher(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &url);

    QString accessToken() const;
    void setAccessToken(const QString &token);

    QString profile() const;
    void setProfile(const QString &profile);

    bool enabled() const;
    bool busy() const;
    bool hasMatch() const;
    double matchedLatitude() const;
    double matchedLongitude() const;
    double confidence() const;
    QString errorString() const;

    Q_INVOKABLE void submitTracePoint(double latitude,
                                      double longitude,
                                      double speedKmh,
                                      double headingDeg,
                                      double timestampMs,
                                      double horizontalAccuracyMeters);
    Q_INVOKABLE void reset();

signals:
    void baseUrlChanged();
    void accessTokenChanged();
    void profileChanged();
    void enabledChanged();
    void busyChanged();
    void matchChanged();
    void errorChanged();

private slots:
    void onReplyFinished(QNetworkReply *reply);

private:
    struct TraceSample {
        double latitude = 0.0;
        double longitude = 0.0;
        qint64 timestampMs = 0;
        double radiusMeters = 0.0;
    };

    bool envEnabled() const;
    void setBusy(bool busy);
    void setErrorString(const QString &error);
    void clearMatch();
    void updateMatch(double latitude, double longitude, double confidence);
    void abortReply();
    QUrl buildRequestUrl() const;

    QNetworkAccessManager m_networkManager;
    QPointer<QNetworkReply> m_reply;
    QString m_baseUrl = QStringLiteral("https://api.mapbox.com");
    QString m_accessToken;
    QString m_profile = QStringLiteral("mapbox/driving-traffic");
    QVector<TraceSample> m_samples;
    QString m_errorString;
    int m_minRequestIntervalMs = 3000;
    int m_minSampleIntervalMs = 1200;
    int m_maxTracePoints = 6;
    double m_minSampleDistanceMeters = 6.0;
    bool m_busy = false;
    bool m_hasMatch = false;
    double m_matchedLatitude = 0.0;
    double m_matchedLongitude = 0.0;
    double m_confidence = 0.0;
    qint64 m_lastRequestMs = 0;
};

#endif // MAPBOXMAPMATCHER_H
