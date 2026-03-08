#include "osrmrouteprovider.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>

OsrmRouteProvider::OsrmRouteProvider(QObject *parent)
    : QObject(parent)
    , m_baseUrl(QStringLiteral("https://router.project-osrm.org"))
{
    connect(&m_nam, &QNetworkAccessManager::finished,
            this, &OsrmRouteProvider::handleReply);
}

OsrmRouteProvider *OsrmRouteProvider::instance()
{
    static OsrmRouteProvider s_instance;
    return &s_instance;
}

void OsrmRouteProvider::setBaseUrl(const QString &url)
{
    if (m_baseUrl == url)
        return;
    m_baseUrl = url;
    emit baseUrlChanged();
}

void OsrmRouteProvider::requestRoute(double fromLat, double fromLon,
                                      double toLat, double toLon)
{
    if (m_busy) {
        qWarning() << "[OsrmRouteProvider] Already fetching a route, skipping";
        return;
    }

    // OSRM expects coordinates as longitude,latitude
    // Format: /route/v1/driving/lon1,lat1;lon2,lat2?geometries=geojson&overview=full
    QString coords = QStringLiteral("%1,%2;%3,%4")
                         .arg(fromLon, 0, 'f', 6)
                         .arg(fromLat, 0, 'f', 6)
                         .arg(toLon, 0, 'f', 6)
                         .arg(toLat, 0, 'f', 6);

    QUrl url(m_baseUrl + QStringLiteral("/route/v1/driving/") + coords);
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("geometries"), QStringLiteral("geojson"));
    query.addQueryItem(QStringLiteral("overview"), QStringLiteral("full"));
    query.addQueryItem(QStringLiteral("steps"), QStringLiteral("false"));
    url.setQuery(query);

    qDebug() << "[OsrmRouteProvider] Requesting route:" << url.toString();

    m_busy = true;
    emit busyChanged();

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("QtInstrumentCluster/1.0"));
    m_nam.get(req);
}

void OsrmRouteProvider::handleReply(QNetworkReply *reply)
{
    reply->deleteLater();

    m_busy = false;
    emit busyChanged();

    if (reply->error() != QNetworkReply::NoError) {
        QString err = QStringLiteral("OSRM network error: ") + reply->errorString();
        qWarning() << "[OsrmRouteProvider]" << err;
        emit routeFailed(err);
        return;
    }

    QByteArray data = reply->readAll();
    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);

    if (parseErr.error != QJsonParseError::NoError) {
        QString err = QStringLiteral("JSON parse error: ") + parseErr.errorString();
        qWarning() << "[OsrmRouteProvider]" << err;
        emit routeFailed(err);
        return;
    }

    QJsonObject root = doc.object();
    QString code = root.value(QStringLiteral("code")).toString();
    if (code != QStringLiteral("Ok")) {
        QString err = QStringLiteral("OSRM returned code: ") + code;
        qWarning() << "[OsrmRouteProvider]" << err;
        emit routeFailed(err);
        return;
    }

    QJsonArray routes = root.value(QStringLiteral("routes")).toArray();
    if (routes.isEmpty()) {
        emit routeFailed(QStringLiteral("No routes returned"));
        return;
    }

    QJsonObject firstRoute = routes.first().toObject();
    m_distanceMeters = firstRoute.value(QStringLiteral("distance")).toDouble();
    m_durationSeconds = firstRoute.value(QStringLiteral("duration")).toDouble();

    QJsonObject geometry = firstRoute.value(QStringLiteral("geometry")).toObject();
    QJsonArray coordinates = geometry.value(QStringLiteral("coordinates")).toArray();

    m_routePath = parseGeoJsonCoordinates(coordinates);

    qDebug() << "[OsrmRouteProvider] Route received:"
             << m_routePath.size() << "points,"
             << m_distanceMeters << "m,"
             << m_durationSeconds << "s";

    emit routePathChanged();
    emit routeReady(m_routePath);
}

QVariantList OsrmRouteProvider::parseGeoJsonCoordinates(const QJsonArray &coordinates) const
{
    QVariantList path;
    path.reserve(coordinates.size());

    for (const QJsonValue &val : coordinates) {
        QJsonArray coord = val.toArray();
        if (coord.size() >= 2) {
            // GeoJSON is [longitude, latitude]
            double lon = coord.at(0).toDouble();
            double lat = coord.at(1).toDouble();
            path.append(QVariant::fromValue(QGeoCoordinate(lat, lon)));
        }
    }

    return path;
}
