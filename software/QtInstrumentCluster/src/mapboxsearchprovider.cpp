#include "mapboxsearchprovider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSet>
#include <QUuid>
#include <QUrl>
#include <QUrlQuery>
#include <QtGlobal>

namespace {

QString apiMessageFromPayload(const QByteArray &payload)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        return QString();
    }

    const QJsonObject root = document.object();
    const QString message = root.value(QStringLiteral("message")).toString().trimmed();
    if (!message.isEmpty()) {
        return message;
    }

    return root.value(QStringLiteral("error")).toString().trimmed();
}

QString featureTypeLabel(const QString &featureType)
{
    if (featureType == QStringLiteral("poi")) return QStringLiteral("POI");
    if (featureType == QStringLiteral("address")) return QStringLiteral("Address");
    if (featureType == QStringLiteral("street")) return QStringLiteral("Street");
    if (featureType == QStringLiteral("neighborhood")) return QStringLiteral("Neighborhood");
    if (featureType == QStringLiteral("locality")) return QStringLiteral("Locality");
    if (featureType == QStringLiteral("city")) return QStringLiteral("City");
    if (featureType == QStringLiteral("place")) return QStringLiteral("Place");
    if (featureType == QStringLiteral("district")) return QStringLiteral("District");
    if (featureType == QStringLiteral("region")) return QStringLiteral("Region");
    if (featureType == QStringLiteral("postcode")) return QStringLiteral("Postcode");
    if (featureType == QStringLiteral("country")) return QStringLiteral("Country");
    return QStringLiteral("Place");
}

bool isFiniteCoordinate(double value)
{
    return qIsFinite(value);
}

} // namespace

MapboxSearchProvider *MapboxSearchProvider::instance()
{
    static MapboxSearchProvider s_instance;
    return &s_instance;
}

MapboxSearchProvider::MapboxSearchProvider(QObject *parent)
    : QObject(parent)
{
    connect(&m_networkManager, &QNetworkAccessManager::finished,
            this, &MapboxSearchProvider::onReplyFinished);

    m_languageCode = qEnvironmentVariable("MAPBOX_SEARCH_LANGUAGE", "vi").trimmed();
    if (m_languageCode.isEmpty()) {
        m_languageCode = QStringLiteral("vi");
    }

    m_countryCode = qEnvironmentVariable("MAPBOX_SEARCH_COUNTRY", "VN").trimmed().toUpper();
    if (m_countryCode.isEmpty()) {
        m_countryCode = QStringLiteral("VN");
    }

    m_types = qEnvironmentVariable(
        "MAPBOX_SEARCH_TYPES",
        "poi,address,street,neighborhood,locality,place,city,district,region,postcode").trimmed();
    if (m_types.isEmpty()) {
        m_types = QStringLiteral("poi,address,street,neighborhood,locality,place,city,district,region,postcode");
    }

    bool limitOk = false;
    const int configuredLimit = qEnvironmentVariableIntValue("MAPBOX_SEARCH_LIMIT", &limitOk);
    if (limitOk) {
        m_limit = qBound(1, configuredLimit, 10);
    }
}

QVariantList MapboxSearchProvider::suggestions() const
{
    return m_suggestions;
}

bool MapboxSearchProvider::loading() const
{
    return m_loading;
}

QString MapboxSearchProvider::errorString() const
{
    return m_errorString;
}

void MapboxSearchProvider::setAccessToken(const QString &token)
{
    m_accessToken = token.trimmed();
}

void MapboxSearchProvider::suggest(const QString &query,
                                   double proximityLatitude,
                                   double proximityLongitude,
                                   bool hasProximity)
{
    const QString trimmedQuery = query.trimmed();
    if (trimmedQuery.length() < 2) {
        clearSuggestionsInternal(true);
        setErrorString(QString());
        return;
    }

    if (m_accessToken.isEmpty()) {
        clearSuggestionsInternal(true);
        setErrorString(QStringLiteral("MAPBOX_ACCESS_TOKEN is missing"));
        return;
    }

    abortReply(m_retrieveReply);
    abortReply(m_suggestReply);
    beginSessionIfNeeded();
    setErrorString(QString());

    QUrl url(QStringLiteral("https://api.mapbox.com/search/searchbox/v1/suggest"));
    QUrlQuery queryItems;
    queryItems.addQueryItem(QStringLiteral("q"), trimmedQuery);
    queryItems.addQueryItem(QStringLiteral("access_token"), m_accessToken);
    queryItems.addQueryItem(QStringLiteral("session_token"), m_sessionToken);
    queryItems.addQueryItem(QStringLiteral("language"), m_languageCode);
    queryItems.addQueryItem(QStringLiteral("limit"), QString::number(m_limit));
    queryItems.addQueryItem(QStringLiteral("types"), m_types);
    if (!m_countryCode.isEmpty()) {
        queryItems.addQueryItem(QStringLiteral("country"), m_countryCode);
    }
    if (hasProximity && isFiniteCoordinate(proximityLatitude) && isFiniteCoordinate(proximityLongitude)) {
        queryItems.addQueryItem(QStringLiteral("proximity"),
                                QStringLiteral("%1,%2")
                                    .arg(proximityLongitude, 0, 'f', 6)
                                    .arg(proximityLatitude, 0, 'f', 6));
    }
    url.setQuery(queryItems);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("QtInstrumentCluster/1.0"));
    request.setTransferTimeout(6000);

    m_suggestReply = m_networkManager.get(request);
    m_suggestReply->setProperty("requestKind", QStringLiteral("suggest"));
    updateLoadingState();
}

void MapboxSearchProvider::retrieveSuggestion(const QString &mapboxId)
{
    const QString trimmedId = mapboxId.trimmed();
    if (trimmedId.isEmpty()) {
        return;
    }

    if (m_accessToken.isEmpty()) {
        setErrorString(QStringLiteral("MAPBOX_ACCESS_TOKEN is missing"));
        return;
    }

    beginSessionIfNeeded();
    abortReply(m_suggestReply);
    abortReply(m_retrieveReply);
    setErrorString(QString());

    QUrl url(QStringLiteral("https://api.mapbox.com/search/searchbox/v1/retrieve/%1")
                 .arg(QString::fromUtf8(QUrl::toPercentEncoding(trimmedId))));
    QUrlQuery queryItems;
    queryItems.addQueryItem(QStringLiteral("access_token"), m_accessToken);
    queryItems.addQueryItem(QStringLiteral("session_token"), m_sessionToken);
    queryItems.addQueryItem(QStringLiteral("language"), m_languageCode);
    url.setQuery(queryItems);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("QtInstrumentCluster/1.0"));
    request.setTransferTimeout(6000);

    m_retrieveReply = m_networkManager.get(request);
    m_retrieveReply->setProperty("requestKind", QStringLiteral("retrieve"));
    updateLoadingState();
}

void MapboxSearchProvider::clearSuggestions()
{
    clearSuggestionsInternal(true);
    setErrorString(QString());
}

void MapboxSearchProvider::onReplyFinished(QNetworkReply *reply)
{
    if (!reply) {
        return;
    }

    const QString requestKind = reply->property("requestKind").toString();
    if (requestKind == QStringLiteral("suggest")) {
        if (reply != m_suggestReply) {
            reply->deleteLater();
            return;
        }
        m_suggestReply = nullptr;
    } else if (requestKind == QStringLiteral("retrieve")) {
        if (reply != m_retrieveReply) {
            reply->deleteLater();
            return;
        }
        m_retrieveReply = nullptr;
    } else {
        reply->deleteLater();
        return;
    }

    const QByteArray payload = reply->readAll();
    const QNetworkReply::NetworkError networkError = reply->error();
    const QString errorText = reply->errorString();
    reply->deleteLater();

    if (networkError == QNetworkReply::OperationCanceledError) {
        updateLoadingState();
        return;
    }

    if (networkError != QNetworkReply::NoError) {
        QString errorMessage = apiMessageFromPayload(payload);
        if (errorMessage.isEmpty()) {
            errorMessage = errorText;
        }
        setErrorString(errorMessage);
        if (requestKind == QStringLiteral("suggest")) {
            setSuggestions(QVariantList());
        } else {
            resetSession();
        }
        updateLoadingState();
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setErrorString(QStringLiteral("Invalid Mapbox Search response"));
        if (requestKind == QStringLiteral("suggest")) {
            setSuggestions(QVariantList());
        } else {
            resetSession();
        }
        updateLoadingState();
        return;
    }

    const QJsonObject root = document.object();
    if (requestKind == QStringLiteral("suggest")) {
        const QJsonArray suggestionArray = root.value(QStringLiteral("suggestions")).toArray();
        QVariantList parsedSuggestions;
        parsedSuggestions.reserve(suggestionArray.size());

        QSet<QString> seenIds;
        for (const QJsonValue &value : suggestionArray) {
            if (!value.isObject()) {
                continue;
            }

            const QVariantMap parsed = parseSuggestion(value.toObject());
            const QString mapboxId = parsed.value(QStringLiteral("mapboxId")).toString();
            if (parsed.isEmpty() || mapboxId.isEmpty() || seenIds.contains(mapboxId)) {
                continue;
            }

            seenIds.insert(mapboxId);
            parsedSuggestions.push_back(parsed);
        }

        setSuggestions(parsedSuggestions);
        setErrorString(QString());
    } else {
        const QJsonArray features = root.value(QStringLiteral("features")).toArray();
        if (features.isEmpty() || !features.first().isObject()) {
            setErrorString(QStringLiteral("No place details returned"));
            resetSession();
            updateLoadingState();
            return;
        }

        const QVariantMap place = parseRetrievedPlace(features.first().toObject());
        if (place.isEmpty()) {
            setErrorString(QStringLiteral("Selected result has no routable coordinates"));
            resetSession();
            updateLoadingState();
            return;
        }

        setSuggestions(QVariantList());
        setErrorString(QString());
        emit placeRetrieved(place);
        resetSession();
    }

    updateLoadingState();
}

void MapboxSearchProvider::beginSessionIfNeeded()
{
    if (!m_sessionToken.isEmpty()) {
        return;
    }

    m_sessionToken = QUuid::createUuid().toString(QUuid::WithoutBraces);
}

void MapboxSearchProvider::resetSession()
{
    m_sessionToken.clear();
}

void MapboxSearchProvider::abortReply(QPointer<QNetworkReply> &reply)
{
    if (!reply) {
        return;
    }

    if (!reply->isFinished()) {
        reply->abort();
    }
    reply = nullptr;
}

void MapboxSearchProvider::clearSuggestionsInternal(bool resetSessionToken)
{
    abortReply(m_suggestReply);
    abortReply(m_retrieveReply);
    setSuggestions(QVariantList());
    if (resetSessionToken) {
        resetSession();
    }
    updateLoadingState();
}

void MapboxSearchProvider::setSuggestions(const QVariantList &suggestions)
{
    if (m_suggestions == suggestions) {
        return;
    }

    m_suggestions = suggestions;
    emit suggestionsChanged();
}

void MapboxSearchProvider::setErrorString(const QString &error)
{
    if (m_errorString == error) {
        return;
    }

    m_errorString = error;
    emit errorChanged();
}

void MapboxSearchProvider::updateLoadingState()
{
    const bool loadingNow = m_suggestReply || m_retrieveReply;
    if (m_loading == loadingNow) {
        return;
    }

    m_loading = loadingNow;
    emit loadingChanged();
}

QVariantMap MapboxSearchProvider::parseSuggestion(const QJsonObject &suggestion) const
{
    const QString featureType = suggestion.value(QStringLiteral("feature_type")).toString().trimmed();
    if (featureType == QStringLiteral("category")) {
        return QVariantMap();
    }

    const QString title = suggestion.value(QStringLiteral("name_preferred")).toString().trimmed().isEmpty()
                              ? suggestion.value(QStringLiteral("name")).toString().trimmed()
                              : suggestion.value(QStringLiteral("name_preferred")).toString().trimmed();
    const QString mapboxId = suggestion.value(QStringLiteral("mapbox_id")).toString().trimmed();
    if (title.isEmpty() || mapboxId.isEmpty()) {
        return QVariantMap();
    }

    const QString fullAddress = suggestion.value(QStringLiteral("full_address")).toString().trimmed();
    const QString address = suggestion.value(QStringLiteral("address")).toString().trimmed();
    const QString placeFormatted = suggestion.value(QStringLiteral("place_formatted")).toString().trimmed();
    const QString subtitle = buildSubtitle(fullAddress, address, placeFormatted);
    const double distanceMeters = suggestion.value(QStringLiteral("distance")).toDouble(-1.0);
    const double etaMinutes = suggestion.value(QStringLiteral("eta")).toDouble(-1.0);

    QVariantMap item;
    item.insert(QStringLiteral("mapboxId"), mapboxId);
    item.insert(QStringLiteral("title"), title);
    item.insert(QStringLiteral("subtitle"), subtitle);
    item.insert(QStringLiteral("displayText"), buildDisplayText(title, subtitle));
    item.insert(QStringLiteral("featureType"), featureType);
    item.insert(QStringLiteral("featureTypeLabel"), featureTypeLabel(featureType));
    item.insert(QStringLiteral("distanceMeters"), distanceMeters >= 0.0 ? distanceMeters : -1.0);
    item.insert(QStringLiteral("etaMinutes"), etaMinutes >= 0.0 ? etaMinutes : -1.0);
    return item;
}

QVariantMap MapboxSearchProvider::parseRetrievedPlace(const QJsonObject &feature) const
{
    const QJsonObject properties = feature.value(QStringLiteral("properties")).toObject();
    if (properties.isEmpty()) {
        return QVariantMap();
    }

    const QString title = properties.value(QStringLiteral("name_preferred")).toString().trimmed().isEmpty()
                              ? properties.value(QStringLiteral("name")).toString().trimmed()
                              : properties.value(QStringLiteral("name_preferred")).toString().trimmed();
    if (title.isEmpty()) {
        return QVariantMap();
    }

    const QString fullAddress = properties.value(QStringLiteral("full_address")).toString().trimmed();
    const QString address = properties.value(QStringLiteral("address")).toString().trimmed();
    const QString placeFormatted = properties.value(QStringLiteral("place_formatted")).toString().trimmed();
    const QString featureType = properties.value(QStringLiteral("feature_type")).toString().trimmed();
    const QString mapboxId = properties.value(QStringLiteral("mapbox_id")).toString().trimmed();

    double longitude = qQNaN();
    double latitude = qQNaN();
    bool hasRoutablePoint = false;

    const QJsonObject coordinates = properties.value(QStringLiteral("coordinates")).toObject();
    const QJsonArray routablePoints = coordinates.value(QStringLiteral("routable_points")).toArray();
    if (!routablePoints.isEmpty() && routablePoints.first().isObject()) {
        const QJsonObject point = routablePoints.first().toObject();
        longitude = point.value(QStringLiteral("longitude")).toDouble(qQNaN());
        latitude = point.value(QStringLiteral("latitude")).toDouble(qQNaN());
        hasRoutablePoint = isFiniteCoordinate(longitude) && isFiniteCoordinate(latitude);
    }

    if (!hasRoutablePoint) {
        longitude = coordinates.value(QStringLiteral("longitude")).toDouble(qQNaN());
        latitude = coordinates.value(QStringLiteral("latitude")).toDouble(qQNaN());
    }

    if (!isFiniteCoordinate(longitude) || !isFiniteCoordinate(latitude)) {
        const QJsonObject geometry = feature.value(QStringLiteral("geometry")).toObject();
        const QJsonArray geometryCoordinates = geometry.value(QStringLiteral("coordinates")).toArray();
        if (geometryCoordinates.size() >= 2) {
            longitude = geometryCoordinates.at(0).toDouble(qQNaN());
            latitude = geometryCoordinates.at(1).toDouble(qQNaN());
        }
    }

    if (!isFiniteCoordinate(longitude) || !isFiniteCoordinate(latitude)) {
        return QVariantMap();
    }

    const QString subtitle = buildSubtitle(fullAddress, address, placeFormatted);

    QVariantMap place;
    place.insert(QStringLiteral("mapboxId"), mapboxId);
    place.insert(QStringLiteral("title"), title);
    place.insert(QStringLiteral("subtitle"), subtitle);
    place.insert(QStringLiteral("displayText"), buildDisplayText(title, subtitle));
    place.insert(QStringLiteral("featureType"), featureType);
    place.insert(QStringLiteral("featureTypeLabel"), featureTypeLabel(featureType));
    place.insert(QStringLiteral("latitude"), latitude);
    place.insert(QStringLiteral("longitude"), longitude);
    place.insert(QStringLiteral("hasRoutablePoint"), hasRoutablePoint);
    place.insert(QStringLiteral("accuracy"),
                 coordinates.value(QStringLiteral("accuracy")).toString().trimmed());
    return place;
}

QString MapboxSearchProvider::buildSubtitle(const QString &fullAddress,
                                            const QString &address,
                                            const QString &placeFormatted) const
{
    if (!fullAddress.isEmpty()) {
        return fullAddress;
    }

    if (!address.isEmpty() && !placeFormatted.isEmpty()) {
        return address + QStringLiteral(", ") + placeFormatted;
    }

    if (!placeFormatted.isEmpty()) {
        return placeFormatted;
    }

    return address;
}

QString MapboxSearchProvider::buildDisplayText(const QString &title,
                                               const QString &subtitle) const
{
    if (subtitle.isEmpty() || subtitle == title) {
        return title;
    }

    return title + QStringLiteral(", ") + subtitle;
}
