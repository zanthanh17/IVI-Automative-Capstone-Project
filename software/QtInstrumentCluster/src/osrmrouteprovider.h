#ifndef OSRMROUTEPROVIDER_H
#define OSRMROUTEPROVIDER_H

#include <QObject>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QGeoCoordinate>
#include <QJsonArray>

/**
 * @brief Provides routing via OSRM HTTP API.
 *
 * Calls the OSRM /route/v1/driving/ endpoint, parses the GeoJSON
 * geometry from the response, and emits the resulting path as a
 * QVariantList of QGeoCoordinate that can be consumed directly
 * in QML MapPolyline.
 */
class OsrmRouteProvider : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString provider READ provider WRITE setProvider NOTIFY providerChanged)
    Q_PROPERTY(QString accessToken READ accessToken WRITE setAccessToken NOTIFY accessTokenChanged)
    Q_PROPERTY(QString profile READ profile WRITE setProfile NOTIFY profileChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QVariantList routePath READ routePath NOTIFY routePathChanged)
    Q_PROPERTY(QVariantList routeSteps READ routeSteps NOTIFY routeStepsChanged)
    Q_PROPERTY(QVariantList alternativeRoutes READ alternativeRoutes NOTIFY alternativeRoutesChanged)
    Q_PROPERTY(int selectedRouteIndex READ selectedRouteIndex NOTIFY selectedRouteChanged)
    Q_PROPERTY(double distanceMeters READ distanceMeters NOTIFY routePathChanged)
    Q_PROPERTY(double durationSeconds READ durationSeconds NOTIFY routePathChanged)

public:
    static OsrmRouteProvider *instance();

    QString baseUrl() const { return m_baseUrl; }
    void setBaseUrl(const QString &url);
    QString provider() const { return m_provider; }
    void setProvider(const QString &provider);
    QString accessToken() const { return m_accessToken; }
    void setAccessToken(const QString &token);
    QString profile() const { return m_profile; }
    void setProfile(const QString &profile);

    bool busy() const { return m_busy; }

    QVariantList routePath() const { return m_routePath; }
    QVariantList routeSteps() const { return m_routeSteps; }
    QVariantList alternativeRoutes() const { return m_alternativeRoutes; }
    int selectedRouteIndex() const { return m_selectedRouteIndex; }
    double distanceMeters() const { return m_distanceMeters; }
    double durationSeconds() const { return m_durationSeconds; }

    /**
     * Request a driving route between two coordinates.
     * Results are emitted via routeReady() / routeFailed().
     */
    Q_INVOKABLE void requestRoute(double fromLat, double fromLon,
                                   double toLat, double toLon);
    Q_INVOKABLE bool selectRoute(int index);

signals:
    void baseUrlChanged();
    void providerChanged();
    void accessTokenChanged();
    void profileChanged();
    void busyChanged();
    void routePathChanged();
    void routeStepsChanged();
    void alternativeRoutesChanged();
    void selectedRouteChanged();
    void routeReady(const QVariantList &path);
    void routeFailed(const QString &error);

private:
    explicit OsrmRouteProvider(QObject *parent = nullptr);
    bool isMapboxProvider() const;
    QUrl buildRequestUrl(double fromLat, double fromLon, double toLat, double toLon) const;
    void applyRouteAtIndex(int index, bool emitRouteReadySignal);

    void handleReply(QNetworkReply *reply);
    QVariantList parseGeoJsonCoordinates(const QJsonArray &coordinates) const;
    QVariantList parseRouteSteps(const QJsonArray &legs) const;
    int parseManeuverType(const QString &modifier, const QString &type) const;

    QNetworkAccessManager m_nam;
    QString m_baseUrl;
    QString m_provider = QStringLiteral("osrm");
    QString m_accessToken;
    QString m_profile = QStringLiteral("mapbox/driving-traffic");
    bool m_busy = false;
    QVariantList m_alternativeRoutes;
    int m_selectedRouteIndex = -1;
    QVariantList m_routePath;
    QVariantList m_routeSteps;
    double m_distanceMeters = 0;
    double m_durationSeconds = 0;
};

#endif // OSRMROUTEPROVIDER_H
