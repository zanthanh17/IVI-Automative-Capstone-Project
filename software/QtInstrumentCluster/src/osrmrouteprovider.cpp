#include "osrmrouteprovider.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>
#include <QVariantMap>

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

void OsrmRouteProvider::setProvider(const QString &provider)
{
    const QString normalized = provider.trimmed().toLower();
    if (normalized.isEmpty() || m_provider == normalized)
        return;
    m_provider = normalized;
    emit providerChanged();
}

void OsrmRouteProvider::setAccessToken(const QString &token)
{
    if (m_accessToken == token)
        return;
    m_accessToken = token;
    emit accessTokenChanged();
}

void OsrmRouteProvider::setProfile(const QString &profile)
{
    if (m_profile == profile || profile.trimmed().isEmpty())
        return;
    m_profile = profile.trimmed();
    emit profileChanged();
}

bool OsrmRouteProvider::isMapboxProvider() const
{
    return m_provider == QStringLiteral("mapbox");
}

QUrl OsrmRouteProvider::buildRequestUrl(double fromLat, double fromLon, double toLat, double toLon) const
{
    const QString coords = QStringLiteral("%1,%2;%3,%4")
                               .arg(fromLon, 0, 'f', 6)
                               .arg(fromLat, 0, 'f', 6)
                               .arg(toLon, 0, 'f', 6)
                               .arg(toLat, 0, 'f', 6);

    QUrl url;
    QUrlQuery query;

    if (isMapboxProvider()) {
        url = QUrl(m_baseUrl + QStringLiteral("/directions/v5/") + m_profile + QStringLiteral("/") + coords);
        query.addQueryItem(QStringLiteral("geometries"), QStringLiteral("geojson"));
        query.addQueryItem(QStringLiteral("overview"), QStringLiteral("full"));
        query.addQueryItem(QStringLiteral("steps"), QStringLiteral("true"));
        query.addQueryItem(QStringLiteral("alternatives"), QStringLiteral("true"));
        query.addQueryItem(QStringLiteral("annotations"),
                           QStringLiteral("duration,distance,speed,congestion_numeric,maxspeed"));
        query.addQueryItem(QStringLiteral("voice_instructions"), QStringLiteral("true"));
        query.addQueryItem(QStringLiteral("banner_instructions"), QStringLiteral("true"));
        query.addQueryItem(QStringLiteral("access_token"), m_accessToken);
    } else {
        url = QUrl(m_baseUrl + QStringLiteral("/route/v1/driving/") + coords);
        query.addQueryItem(QStringLiteral("geometries"), QStringLiteral("geojson"));
        query.addQueryItem(QStringLiteral("overview"), QStringLiteral("full"));
        query.addQueryItem(QStringLiteral("steps"), QStringLiteral("true"));
    }

    url.setQuery(query);
    return url;
}

void OsrmRouteProvider::requestRoute(double fromLat, double fromLon,
                                      double toLat, double toLon)
{
    if (m_busy) {
        qWarning() << "[OsrmRouteProvider] Already fetching a route, skipping";
        return;
    }

    if (isMapboxProvider() && m_accessToken.trimmed().isEmpty()) {
        emit routeFailed(QStringLiteral("Mapbox provider selected but MAPBOX_ACCESS_TOKEN is missing"));
        return;
    }

    const QUrl url = buildRequestUrl(fromLat, fromLon, toLat, toLon);

    qDebug() << "[OsrmRouteProvider] Requesting route:" << url.toString();

    m_busy = true;
    emit busyChanged();

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("QtInstrumentCluster/1.0"));
    m_nam.get(req);
}

bool OsrmRouteProvider::selectRoute(int index)
{
    if (index < 0 || index >= m_alternativeRoutes.size()) {
        return false;
    }
    applyRouteAtIndex(index, true);
    return true;
}

void OsrmRouteProvider::applyRouteAtIndex(int index, bool emitRouteReadySignal)
{
    if (index < 0 || index >= m_alternativeRoutes.size()) {
        return;
    }

    const QVariantMap route = m_alternativeRoutes.at(index).toMap();
    const QVariantList path = route.value(QStringLiteral("path")).toList();
    const QVariantList steps = route.value(QStringLiteral("steps")).toList();
    const double distance = route.value(QStringLiteral("distanceMeters")).toDouble();
    const double duration = route.value(QStringLiteral("durationSeconds")).toDouble();

    const bool pathChanged = (m_routePath != path);
    const bool stepsChanged = (m_routeSteps != steps);
    const bool metricsChanged = !qFuzzyCompare(m_distanceMeters + 1.0, distance + 1.0)
                                || !qFuzzyCompare(m_durationSeconds + 1.0, duration + 1.0);
    const bool indexChanged = (m_selectedRouteIndex != index);

    m_routePath = path;
    m_routeSteps = steps;
    m_distanceMeters = distance;
    m_durationSeconds = duration;
    m_selectedRouteIndex = index;

    if (indexChanged) {
        emit selectedRouteChanged();
    }
    if (pathChanged || metricsChanged) {
        emit routePathChanged();
    }
    if (stepsChanged) {
        emit routeStepsChanged();
    }
    if (emitRouteReadySignal) {
        emit routeReady(m_routePath);
    }
}

void OsrmRouteProvider::handleReply(QNetworkReply *reply)
{
    reply->deleteLater();

    m_busy = false;
    emit busyChanged();

    if (reply->error() != QNetworkReply::NoError) {
        const QString service = isMapboxProvider() ? QStringLiteral("Mapbox") : QStringLiteral("OSRM");
        QString err = service + QStringLiteral(" network error: ") + reply->errorString();
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
        const QString message = root.value(QStringLiteral("message")).toString();
        const QString service = isMapboxProvider() ? QStringLiteral("Mapbox") : QStringLiteral("OSRM");
        QString err = service + QStringLiteral(" returned code: ") + code;
        if (!message.isEmpty()) {
            err += QStringLiteral(" (") + message + QStringLiteral(")");
        }
        qWarning() << "[OsrmRouteProvider]" << err;
        emit routeFailed(err);
        return;
    }

    QJsonArray routes = root.value(QStringLiteral("routes")).toArray();
    if (routes.isEmpty()) {
        emit routeFailed(QStringLiteral("No routes returned"));
        return;
    }

    QVariantList alternatives;
    alternatives.reserve(routes.size());

    for (const QJsonValue &routeVal : routes) {
        const QJsonObject routeObj = routeVal.toObject();
        const QJsonObject geometry = routeObj.value(QStringLiteral("geometry")).toObject();
        const QJsonArray coordinates = geometry.value(QStringLiteral("coordinates")).toArray();
        const QJsonArray legs = routeObj.value(QStringLiteral("legs")).toArray();

        QVariantMap item;
        item.insert(QStringLiteral("distanceMeters"), routeObj.value(QStringLiteral("distance")).toDouble());
        item.insert(QStringLiteral("durationSeconds"), routeObj.value(QStringLiteral("duration")).toDouble());
        item.insert(QStringLiteral("path"), parseGeoJsonCoordinates(coordinates));
        item.insert(QStringLiteral("steps"), parseRouteSteps(legs));
        alternatives.append(item);
    }

    m_alternativeRoutes = alternatives;
    emit alternativeRoutesChanged();

    const int defaultIndex = 0;
    applyRouteAtIndex(defaultIndex, false);

    qDebug() << "[OsrmRouteProvider] Route received:"
             << m_routePath.size() << "points,"
             << m_distanceMeters << "m,"
             << m_durationSeconds << "s,"
             << "alternatives:" << m_alternativeRoutes.size();

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

QVariantList OsrmRouteProvider::parseRouteSteps(const QJsonArray &legs) const
{
    QVariantList stepsList;
    if (legs.isEmpty()) return stepsList;

    // Usually driving routes have 1 leg between 2 points
    const QJsonObject firstLeg = legs.first().toObject();
    const QJsonArray steps = firstLeg.value(QStringLiteral("steps")).toArray();

    for (int i = 0; i < steps.size(); ++i) {
        const QJsonObject stepObj = steps.at(i).toObject();
        const QJsonObject maneuver = stepObj.value(QStringLiteral("maneuver")).toObject();
        
        QString street = stepObj.value(QStringLiteral("name")).toString();
        
        // Find next street name if available
        QString nextStreet = QStringLiteral("");
        if (i + 1 < steps.size()) {
            nextStreet = steps.at(i + 1).toObject().value(QStringLiteral("name")).toString();
        }

        QString type = maneuver.value(QStringLiteral("type")).toString();
        QString modifier = maneuver.value(QStringLiteral("modifier")).toString();
        
        int maneuverEnum = parseManeuverType(modifier, type);
        double dist = stepObj.value(QStringLiteral("distance")).toDouble();

        QVariantMap stepMap;
        stepMap.insert(QStringLiteral("street"), street);
        stepMap.insert(QStringLiteral("next"), nextStreet);
        stepMap.insert(QStringLiteral("maneuver"), maneuverEnum);
        stepMap.insert(QStringLiteral("dist"), dist);
        
        stepsList.append(stepMap);
    }

    return stepsList;
}

int OsrmRouteProvider::parseManeuverType(const QString &modifier, const QString &type) const
{
    // Mapbox/OSRM Maneuvers -> NavigationModel Enums
    // enum Maneuver { TurnLeft = 0, TurnRight = 1, GoStraight = 2, UTurn = 3, Arrive = 4 }
    if (type == QStringLiteral("arrive")) {
        return 4; // Arrive
    }
    
    if (modifier.contains(QStringLiteral("left"))) {
        return 0; // TurnLeft
    } else if (modifier.contains(QStringLiteral("right"))) {
        return 1; // TurnRight
    } else if (modifier.contains(QStringLiteral("uturn"))) {
        return 3; // UTurn
    }
    
    return 2; // GoStraight (default)
}

