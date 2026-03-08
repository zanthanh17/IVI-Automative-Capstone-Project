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
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QVariantList routePath READ routePath NOTIFY routePathChanged)
    Q_PROPERTY(double distanceMeters READ distanceMeters NOTIFY routePathChanged)
    Q_PROPERTY(double durationSeconds READ durationSeconds NOTIFY routePathChanged)

public:
    static OsrmRouteProvider *instance();

    QString baseUrl() const { return m_baseUrl; }
    void setBaseUrl(const QString &url);

    bool busy() const { return m_busy; }

    QVariantList routePath() const { return m_routePath; }
    double distanceMeters() const { return m_distanceMeters; }
    double durationSeconds() const { return m_durationSeconds; }

    /**
     * Request a driving route between two coordinates.
     * Results are emitted via routeReady() / routeFailed().
     */
    Q_INVOKABLE void requestRoute(double fromLat, double fromLon,
                                   double toLat, double toLon);

signals:
    void baseUrlChanged();
    void busyChanged();
    void routePathChanged();
    void routeReady(const QVariantList &path);
    void routeFailed(const QString &error);

private:
    explicit OsrmRouteProvider(QObject *parent = nullptr);

    void handleReply(QNetworkReply *reply);
    QVariantList parseGeoJsonCoordinates(const QJsonArray &coordinates) const;

    QNetworkAccessManager m_nam;
    QString m_baseUrl;
    bool m_busy = false;
    QVariantList m_routePath;
    double m_distanceMeters = 0;
    double m_durationSeconds = 0;
};

#endif // OSRMROUTEPROVIDER_H
