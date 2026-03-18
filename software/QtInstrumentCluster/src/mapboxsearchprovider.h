#ifndef MAPBOXSEARCHPROVIDER_H
#define MAPBOXSEARCHPROVIDER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QVariantList>

class QJsonObject;
class QNetworkReply;

class MapboxSearchProvider : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList suggestions READ suggestions NOTIFY suggestionsChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)

public:
    static MapboxSearchProvider *instance();

    explicit MapboxSearchProvider(QObject *parent = nullptr);

    QVariantList suggestions() const;
    bool loading() const;
    QString errorString() const;

    void setAccessToken(const QString &token);

    Q_INVOKABLE void suggest(const QString &query,
                             double proximityLatitude,
                             double proximityLongitude,
                             bool hasProximity);
    Q_INVOKABLE void retrieveSuggestion(const QString &mapboxId);
    Q_INVOKABLE void clearSuggestions();

signals:
    void suggestionsChanged();
    void loadingChanged();
    void errorChanged();
    void placeRetrieved(const QVariantMap &place);

private slots:
    void onReplyFinished(QNetworkReply *reply);

private:
    void beginSessionIfNeeded();
    void resetSession();
    void abortReply(QPointer<QNetworkReply> &reply);
    void clearSuggestionsInternal(bool resetSessionToken);
    void setSuggestions(const QVariantList &suggestions);
    void setErrorString(const QString &error);
    void updateLoadingState();

    QVariantMap parseSuggestion(const QJsonObject &suggestion) const;
    QVariantMap parseRetrievedPlace(const QJsonObject &feature) const;
    QString buildSubtitle(const QString &fullAddress,
                          const QString &address,
                          const QString &placeFormatted) const;
    QString buildDisplayText(const QString &title,
                             const QString &subtitle) const;

    QNetworkAccessManager m_networkManager;
    QPointer<QNetworkReply> m_suggestReply;
    QPointer<QNetworkReply> m_retrieveReply;
    QVariantList m_suggestions;
    QString m_errorString;
    QString m_accessToken;
    QString m_sessionToken;
    QString m_languageCode;
    QString m_countryCode;
    QString m_types;
    int m_limit = 8;
    bool m_loading = false;
};

#endif // MAPBOXSEARCHPROVIDER_H
