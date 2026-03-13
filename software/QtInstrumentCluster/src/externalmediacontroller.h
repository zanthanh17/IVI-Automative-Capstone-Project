#ifndef EXTERNALMEDIACONTROLLER_H
#define EXTERNALMEDIACONTROLLER_H

#include <QObject>
#include <QStringList>

#if defined(Q_OS_LINUX)
#include <QDBusObjectPath>
#endif

class QMediaPlayer;
class QProcess;
class QTimer;

class ExternalMediaController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(QString currentSong READ currentSong NOTIFY currentSongChanged)
    Q_PROPERTY(QString currentArtist READ currentArtist NOTIFY currentArtistChanged)
    Q_PROPERTY(bool hostModeEnabled READ hostModeEnabled WRITE setHostModeEnabled NOTIFY hostModeEnabledChanged)

public:
    static ExternalMediaController *instance();

    explicit ExternalMediaController(QObject *parent = nullptr);
    ~ExternalMediaController() override;

    bool available() const;
    bool playing() const;
    QString currentSong() const;
    QString currentArtist() const;

    bool hostModeEnabled() const;
    void setHostModeEnabled(bool enabled);

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePlayback();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void rescan();
    void handleBluetoothDeviceConnectionChanged(const QString &address, bool connected);

signals:
    void availableChanged();
    void playingChanged();
    void currentSongChanged();
    void currentArtistChanged();
    void hostModeEnabledChanged();

private:
    QStringList scanTracks() const;
    void loadTrack(int index, bool autoPlay);
    void emitTrackMetaChanged();
    QString fileNameFallback(const QString &path) const;
    void setSystemSessionState(bool available, bool playing, const QString &song, const QString &artist);
    void probeSystemSession();
    void applySystemSessionPayload(const QString &jsonPayload);
    bool sendSystemCommand(const QString &command);
    QString sessionProbeScript() const;
    QString sessionCommandScript(const QString &command) const;

#if defined(Q_OS_LINUX)
    void connectPlayerSignals();
    void disconnectPlayerSignals();
    void subscribeBluezSignals();
    void pollLinuxPlayerSnapshot();
    void scheduleLinuxDeferredProbes(const QList<int> &delaysMs);
#endif

private slots:
#if defined(Q_OS_LINUX)
    void onPlayerPropertiesChanged(const QString &interface,
                                   const QVariantMap &changedProps,
                                   const QStringList &invalidated);
    void onBluezInterfacesAdded(const QDBusObjectPath &objectPath,
                                const QVariantMap &interfaces);
    void onBluezInterfacesRemoved(const QDBusObjectPath &objectPath,
                                  const QStringList &interfaces);
#endif

private:
    QMediaPlayer *m_player;
    QProcess *m_probeProcess;
    QTimer *m_probeTimer;
    QStringList m_tracks;
    int m_index;
    bool m_hostModeEnabled;
    bool m_proxyPlaying;

    bool m_systemSessionAvailable;
    bool m_systemPlaying;
    QString m_systemSong;
    QString m_systemArtist;
    QString m_linuxPlayerPath;
    QString m_linuxPlayerPathConnected;  // path currently subscribed to signals
#if defined(Q_OS_LINUX)
    int m_linuxNoPathPollCounter;
    qint64 m_linuxLastRealtimeEventMs;
#endif
};

#endif // EXTERNALMEDIACONTROLLER_H
