#include "externalmediacontroller.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMediaContent>
#include <QMediaPlayer>
#include <QMediaMetaData>
#include <QMetaType>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#if defined(Q_OS_LINUX)
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVariant>
#endif

#if defined(Q_OS_LINUX)
namespace {
using DBusProperties = QVariantMap;
using DBusInterfaceMap = QMap<QString, DBusProperties>;
using DBusManagedObjects = QMap<QDBusObjectPath, DBusInterfaceMap>;

const QDBusArgument &operator>>(const QDBusArgument &argument, DBusInterfaceMap &map)
{
    map.clear();
    argument.beginMap();
    while (!argument.atEnd()) {
        QString interfaceName;
        DBusProperties properties;
        argument.beginMapEntry();
        argument >> interfaceName >> properties;
        argument.endMapEntry();
        map.insert(interfaceName, properties);
    }
    argument.endMap();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, DBusManagedObjects &map)
{
    map.clear();
    argument.beginMap();
    while (!argument.atEnd()) {
        QDBusObjectPath objectPath;
        DBusInterfaceMap interfaceMap;
        argument.beginMapEntry();
        argument >> objectPath >> interfaceMap;
        argument.endMapEntry();
        map.insert(objectPath, interfaceMap);
    }
    argument.endMap();
    return argument;
}

QString trackArtistFromVariant(const QVariant &artistValue)
{
    if (artistValue.type() == QVariant::StringList) {
        return artistValue.toStringList().join(", ");
    }
    if (artistValue.type() == QVariant::List) {
        QStringList artists;
        const QVariantList values = artistValue.toList();
        for (const QVariant &value : values) {
            const QString artist = value.toString().trimmed();
            if (!artist.isEmpty()) {
                artists << artist;
            }
        }
        return artists.join(", ");
    }
    return artistValue.toString();
}

QVariant unwrapDBusVariant(const QVariant &value)
{
    QVariant result = value;
    while (result.canConvert<QDBusVariant>()) {
        result = result.value<QDBusVariant>().variant();
    }
    return result;
}
} // namespace
#endif

ExternalMediaController *ExternalMediaController::instance()
{
    static ExternalMediaController *s_instance = nullptr;
    if (!s_instance) {
        s_instance = new ExternalMediaController();
    }
    return s_instance;
}

ExternalMediaController::ExternalMediaController(QObject *parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_probeProcess(new QProcess(this))
    , m_probeTimer(new QTimer(this))
    , m_index(-1)
    , m_hostModeEnabled(true)
    , m_proxyPlaying(false)
    , m_systemSessionAvailable(false)
    , m_systemPlaying(false)
    , m_linuxPlayerPath()
    , m_linuxPlayerPathConnected()
#if defined(Q_OS_LINUX)
    , m_linuxNoPathPollCounter(0)
    , m_linuxLastRealtimeEventMs(0)
#endif
{
    m_player->setVolume(100);

    connect(m_player, &QMediaPlayer::stateChanged, this, &ExternalMediaController::playingChanged);
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus status) {
        if (status == QMediaPlayer::EndOfMedia) {
            next();
        }
    });
    connect(m_player, QOverload<>::of(&QMediaPlayer::metaDataChanged), this, [this]() {
        emitTrackMetaChanged();
    });

    connect(m_probeProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
        const QByteArray raw = m_probeProcess->readAllStandardOutput();
        QString payload = QString::fromUtf8(raw).trimmed();
        if (payload.isEmpty()) {
            payload = QString::fromLocal8Bit(raw).trimmed();
        }
        applySystemSessionPayload(payload);
    });

#if defined(Q_OS_WIN)
    /* Windows: poll via PowerShell (no signal-based alternative) */
    m_probeTimer->setInterval(5000);
    connect(m_probeTimer, &QTimer::timeout, this, &ExternalMediaController::probeSystemSession);
    m_probeTimer->start();
#endif

    rescan();

#if defined(Q_OS_LINUX)
    /* Linux: subscribe to BlueZ D-Bus signals for reactive detection */
    subscribeBluezSignals();
    m_probeTimer->setInterval(900);
    connect(m_probeTimer, &QTimer::timeout, this, [this]() {
        if (!m_hostModeEnabled) {
            return;
        }
        const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
        if (m_linuxPlayerPath.isEmpty()) {
            ++m_linuxNoPathPollCounter;
            if ((m_linuxNoPathPollCounter % 3) == 0) {
                probeSystemSession();
            }
            return;
        }
        m_linuxNoPathPollCounter = 0;
        if (m_linuxLastRealtimeEventMs > 0 &&
            (nowMs - m_linuxLastRealtimeEventMs) < 2200) {
            return;
        }
        pollLinuxPlayerSnapshot();
    });
    m_probeTimer->start();
    /* Defer initial probe to avoid blocking UI at startup */
    QTimer::singleShot(2000, this, &ExternalMediaController::probeSystemSession);
#elif defined(Q_OS_WIN)
    QTimer::singleShot(2000, this, &ExternalMediaController::probeSystemSession);
#endif
}

ExternalMediaController::~ExternalMediaController() = default;

bool ExternalMediaController::available() const
{
    return m_systemSessionAvailable || !m_tracks.isEmpty();
}

bool ExternalMediaController::playing() const
{
    if (m_systemSessionAvailable) {
        return m_systemPlaying;
    }
    if (!m_tracks.isEmpty()) {
        return m_player->state() == QMediaPlayer::PlayingState;
    }
    return m_proxyPlaying;
}

QString ExternalMediaController::fileNameFallback(const QString &path) const
{
    return QFileInfo(path).completeBaseName();
}

QString ExternalMediaController::currentSong() const
{
    if (m_systemSessionAvailable && !m_systemSong.isEmpty()) {
        return m_systemSong;
    }

    const QString metaTitle = m_player->metaData(QMediaMetaData::Title).toString();
    if (!metaTitle.isEmpty()) {
        return metaTitle;
    }
    if (m_index >= 0 && m_index < m_tracks.size()) {
        return fileNameFallback(m_tracks[m_index]);
    }
    return QString();
}

QString ExternalMediaController::currentArtist() const
{
    if (m_systemSessionAvailable && !m_systemArtist.isEmpty()) {
        return m_systemArtist;
    }

    const QString metaArtist = m_player->metaData(QMediaMetaData::ContributingArtist).toStringList().join(", ");
    if (!metaArtist.isEmpty()) {
        return metaArtist;
    }
    if (!m_tracks.isEmpty()) {
        return QStringLiteral("Host media");
    }
    return QString();
}

void ExternalMediaController::setSystemSessionState(bool available,
                                                    bool playing,
                                                    const QString &song,
                                                    const QString &artist)
{
    const bool oldAvailable = m_systemSessionAvailable;
    const bool oldPlaying = m_systemPlaying;
    const QString oldSong = m_systemSong;
    const QString oldArtist = m_systemArtist;

    m_systemSessionAvailable = available;
    m_systemPlaying = available ? playing : false;
    m_systemSong = available ? song : QString();
    m_systemArtist = available ? artist : QString();
    if (!available) {
        m_linuxPlayerPath.clear();
#if defined(Q_OS_LINUX)
        disconnectPlayerSignals();
        m_linuxLastRealtimeEventMs = 0;
#endif
    }

    if (oldAvailable != m_systemSessionAvailable) emit availableChanged();
    if (oldPlaying != m_systemPlaying) emit playingChanged();
    if (oldSong != m_systemSong) emit currentSongChanged();
    if (oldArtist != m_systemArtist) emit currentArtistChanged();
}

bool ExternalMediaController::hostModeEnabled() const
{
    return m_hostModeEnabled;
}

void ExternalMediaController::setHostModeEnabled(bool enabled)
{
    if (m_hostModeEnabled == enabled) {
        return;
    }
    m_hostModeEnabled = enabled;
    emit hostModeEnabledChanged();
#if defined(Q_OS_LINUX)
    if (m_hostModeEnabled) {
        m_linuxNoPathPollCounter = 0;
        m_linuxLastRealtimeEventMs = 0;
        if (!m_probeTimer->isActive()) {
            m_probeTimer->start();
        }
    } else if (m_probeTimer->isActive()) {
        m_probeTimer->stop();
    }
#endif
    probeSystemSession();
}

QStringList ExternalMediaController::scanTracks() const
{
    QStringList files;
    const QStringList nameFilters = {"*.mp3", "*.wav", "*.m4a", "*.flac", "*.ogg"};

    const QString projectMusicDir = QCoreApplication::applicationDirPath() + "/../music";
    QDir projectDir(projectMusicDir);
    if (projectDir.exists()) {
        const QFileInfoList entries = projectDir.entryInfoList(nameFilters, QDir::Files, QDir::Name);
        for (const QFileInfo &fi : entries) {
            files << fi.absoluteFilePath();
        }
    }

    const QStringList musicLocations = QStandardPaths::standardLocations(QStandardPaths::MusicLocation);
    if (!musicLocations.isEmpty()) {
        QDir userMusic(musicLocations.first());
        const QFileInfoList entries = userMusic.entryInfoList(nameFilters, QDir::Files, QDir::Name);
        for (const QFileInfo &fi : entries) {
            files << fi.absoluteFilePath();
            if (files.size() >= 200) {
                break;
            }
        }
    }

    files.removeDuplicates();
    return files;
}

void ExternalMediaController::emitTrackMetaChanged()
{
    emit currentSongChanged();
    emit currentArtistChanged();
}

void ExternalMediaController::loadTrack(int index, bool autoPlay)
{
    if (m_tracks.isEmpty()) {
        m_player->stop();
        m_index = -1;
        emitTrackMetaChanged();
        return;
    }

    int bounded = index % m_tracks.size();
    if (bounded < 0) {
        bounded += m_tracks.size();
    }
    m_index = bounded;
    m_player->setMedia(QMediaContent(QUrl::fromLocalFile(m_tracks[m_index])));
    emitTrackMetaChanged();
    if (autoPlay) {
        m_player->play();
    }
}

QString ExternalMediaController::sessionProbeScript() const
{
    return QStringLiteral(
R"PS(
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]

$asTask=([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and
    $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
} | Select-Object -First 1)

function AwaitTyped([object]$op,[Type]$resultType,[object]$asTaskMethod) {
    $g=$asTaskMethod.MakeGenericMethod($resultType)
    $t=$g.Invoke($null,@($op))
    $t.Wait()
    return $t.Result
}

$mgrType=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
$propType=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime]

$mgr=AwaitTyped ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) $mgrType $asTask
$session=$mgr.GetCurrentSession()
if(-not $session) {
    [ordered]@{ available=$false } | ConvertTo-Json -Compress
    exit 0
}

$props=AwaitTyped ($session.TryGetMediaPropertiesAsync()) $propType $asTask
$playback=$session.GetPlaybackInfo()
$status='Unknown'
if($playback -and $playback.PlaybackStatus) { $status=$playback.PlaybackStatus.ToString() }

[ordered]@{
    available=$true
    title=$props.Title
    artist=$props.Artist
    status=$status
} | ConvertTo-Json -Compress
)PS");
}

QString ExternalMediaController::sessionCommandScript(const QString &command) const
{
    QString action;
    if (command == QStringLiteral("play")) action = QStringLiteral("TryPlayAsync");
    else if (command == QStringLiteral("pause")) action = QStringLiteral("TryPauseAsync");
    else if (command == QStringLiteral("next")) action = QStringLiteral("TrySkipNextAsync");
    else if (command == QStringLiteral("previous")) action = QStringLiteral("TrySkipPreviousAsync");
    else action = QStringLiteral("TryTogglePlayPauseAsync");

    return QStringLiteral(
R"PS(
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]

$asTask=([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and
    $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
} | Select-Object -First 1)

function AwaitTyped([object]$op,[Type]$resultType,[object]$asTaskMethod) {
    $g=$asTaskMethod.MakeGenericMethod($resultType)
    $t=$g.Invoke($null,@($op))
    $t.Wait()
    return $t.Result
}

$mgrType=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
$mgr=AwaitTyped ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) $mgrType $asTask
$session=$mgr.GetCurrentSession()
if(-not $session) { 'false'; exit 0 }

$boolResult=AwaitTyped ($session.%1()) ([System.Boolean]) $asTask
if($boolResult) { 'true' } else { 'false' }
)PS").arg(action);
}

void ExternalMediaController::probeSystemSession()
{
#if defined(Q_OS_WIN)
    if (m_probeProcess->state() != QProcess::NotRunning) {
        return;
    }
    m_probeProcess->start(QStringLiteral("powershell"),
                          {QStringLiteral("-NoProfile"),
                           QStringLiteral("-ExecutionPolicy"), QStringLiteral("Bypass"),
                           QStringLiteral("-Command"), sessionProbeScript()});
#elif defined(Q_OS_LINUX)
    QDBusInterface objectManager(QStringLiteral("org.bluez"),
                                 QStringLiteral("/"),
                                 QStringLiteral("org.freedesktop.DBus.ObjectManager"),
                                 QDBusConnection::systemBus());
    objectManager.setTimeout(1500);  /* Prevent indefinite blocking */
    if (!objectManager.isValid()) {
        setSystemSessionState(false, false, QString(), QString());
        return;
    }

    const QDBusMessage reply = objectManager.callWithArgumentList(
        QDBus::Block, QStringLiteral("GetManagedObjects"), QList<QVariant>());
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
        setSystemSessionState(false, false, QString(), QString());
        return;
    }

    DBusManagedObjects managedObjects;
    const QDBusArgument managedArg = reply.arguments().constFirst().value<QDBusArgument>();
    managedArg >> managedObjects;

    QString playerPath;
    QVariantMap playerProps;

    // Prefer active player from connected MediaControl1 object.
    for (auto it = managedObjects.cbegin(); it != managedObjects.cend(); ++it) {
        const DBusInterfaceMap interfaces = it.value();
        if (!interfaces.contains(QStringLiteral("org.bluez.MediaControl1"))) {
            continue;
        }
        const QVariantMap controlProps = interfaces.value(QStringLiteral("org.bluez.MediaControl1"));
        if (!controlProps.value(QStringLiteral("Connected")).toBool()) {
            continue;
        }

        const QDBusObjectPath playerObjectPath = qvariant_cast<QDBusObjectPath>(controlProps.value(QStringLiteral("Player")));
        const QString candidatePath = playerObjectPath.path();
        if (candidatePath.isEmpty() || candidatePath == QStringLiteral("/")) {
            continue;
        }
        const auto playerIt = managedObjects.find(QDBusObjectPath(candidatePath));
        if (playerIt == managedObjects.end()) {
            continue;
        }
        const DBusInterfaceMap candidateInterfaces = playerIt.value();
        if (!candidateInterfaces.contains(QStringLiteral("org.bluez.MediaPlayer1"))) {
            continue;
        }
        playerPath = candidatePath;
        playerProps = candidateInterfaces.value(QStringLiteral("org.bluez.MediaPlayer1"));
        break;
    }

    // Fallback: first available MediaPlayer1 object.
    if (playerPath.isEmpty()) {
        for (auto it = managedObjects.cbegin(); it != managedObjects.cend(); ++it) {
            const DBusInterfaceMap interfaces = it.value();
            if (!interfaces.contains(QStringLiteral("org.bluez.MediaPlayer1"))) {
                continue;
            }
            playerPath = it.key().path();
            playerProps = interfaces.value(QStringLiteral("org.bluez.MediaPlayer1"));
            break;
        }
    }

    if (playerPath.isEmpty()) {
        setSystemSessionState(false, false, QString(), QString());
        return;
    }

    m_linuxPlayerPath = playerPath;

    // ---------- Fetch properties via Properties.GetAll ----------
    QDBusInterface propsIface(QStringLiteral("org.bluez"),
                              playerPath,
                              QStringLiteral("org.freedesktop.DBus.Properties"),
                              QDBusConnection::systemBus());
    propsIface.setTimeout(1500);  /* Prevent indefinite blocking */

    QString status;
    QString title;
    QString artist;

    if (propsIface.isValid()) {
        // --- 1. Get Status ---
        const QDBusMessage statusReply = propsIface.call(
            QStringLiteral("Get"),
            QStringLiteral("org.bluez.MediaPlayer1"),
            QStringLiteral("Status"));
        if (statusReply.type() == QDBusMessage::ReplyMessage && !statusReply.arguments().isEmpty()) {
            // Properties.Get returns variant(variant(string))
            const QVariant outer = statusReply.arguments().constFirst();
            const QDBusVariant dbusVar = outer.value<QDBusVariant>();
            status = dbusVar.variant().toString();
        }
        qDebug() << "[ExternalMedia] Player:" << playerPath << "Status:" << status;

        // --- 2. Get Track dict ---
        const QDBusMessage trackReply = propsIface.call(
            QStringLiteral("Get"),
            QStringLiteral("org.bluez.MediaPlayer1"),
            QStringLiteral("Track"));

        QVariantMap track;
        if (trackReply.type() == QDBusMessage::ReplyMessage && !trackReply.arguments().isEmpty()) {
            // Properties.Get wraps in variant → the inner value is a{sv} (QDBusArgument)
            const QDBusVariant outerVar = trackReply.arguments().constFirst().value<QDBusVariant>();
            const QVariant innerVal = outerVar.variant();

            if (innerVal.canConvert<QDBusArgument>()) {
                const QDBusArgument trackArg = innerVal.value<QDBusArgument>();
                trackArg >> track;
            } else {
                track = innerVal.toMap();
            }
        } else {
            qDebug() << "[ExternalMedia] Track property error:"
                     << (trackReply.type() == QDBusMessage::ErrorMessage
                         ? trackReply.errorMessage() : "empty reply");
        }

        if (!track.isEmpty()) {
            qDebug() << "[ExternalMedia] Track keys:" << track.keys();
            qDebug() << "[ExternalMedia] Track values:" << track;
        } else {
            qDebug() << "[ExternalMedia] Track dict is EMPTY";
        }

        title = track.value(QStringLiteral("Title")).toString();
        artist = trackArtistFromVariant(track.value(QStringLiteral("Artist")));

        qDebug() << "[ExternalMedia] Title:" << title << "Artist:" << artist;
    } else {
        qDebug() << "[ExternalMedia] Properties interface invalid for" << playerPath;
    }

    const bool isPlaying = status.compare(QStringLiteral("playing"), Qt::CaseInsensitive) == 0;
    setSystemSessionState(true, isPlaying, title, artist);
    m_linuxLastRealtimeEventMs = QDateTime::currentMSecsSinceEpoch();

    // Subscribe to PropertiesChanged signal for real-time metadata updates
    // iPhone sends Track metadata ONLY via this signal, not via Properties.Get
    connectPlayerSignals();
#else
    setSystemSessionState(false, false, QString(), QString());
#endif
}

void ExternalMediaController::applySystemSessionPayload(const QString &jsonPayload)
{
#if !defined(Q_OS_WIN)
    Q_UNUSED(jsonPayload)
    return;
#else
    if (jsonPayload.isEmpty()) {
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return;
    }

    const QJsonObject obj = doc.object();
    const bool available = obj.value(QStringLiteral("available")).toBool(false);
    const QString title = obj.value(QStringLiteral("title")).toString();
    const QString artist = obj.value(QStringLiteral("artist")).toString();
    const QString status = obj.value(QStringLiteral("status")).toString();
    const bool isPlaying = status.compare(QStringLiteral("Playing"), Qt::CaseInsensitive) == 0;

    setSystemSessionState(available, isPlaying, title, artist);
#endif
}

bool ExternalMediaController::sendSystemCommand(const QString &command)
{
#if defined(Q_OS_WIN)
    QProcess cmd;
    cmd.start(QStringLiteral("powershell"),
              {QStringLiteral("-NoProfile"),
               QStringLiteral("-ExecutionPolicy"), QStringLiteral("Bypass"),
               QStringLiteral("-Command"), sessionCommandScript(command)});
    if (!cmd.waitForFinished(2500)) {
        return false;
    }
    const QString out = QString::fromUtf8(cmd.readAllStandardOutput()).trimmed().toLower();
    probeSystemSession();
    return out.contains(QStringLiteral("true"));
#elif defined(Q_OS_LINUX)
    if (m_linuxPlayerPath.isEmpty()) {
        probeSystemSession();
    }
    if (m_linuxPlayerPath.isEmpty()) {
        return false;
    }

    QString method;
    if (command == QStringLiteral("play")) method = QStringLiteral("Play");
    else if (command == QStringLiteral("pause")) method = QStringLiteral("Pause");
    else if (command == QStringLiteral("next")) method = QStringLiteral("Next");
    else if (command == QStringLiteral("previous")) method = QStringLiteral("Previous");
    else if (command == QStringLiteral("stop")) method = QStringLiteral("Stop");
    else {
        qWarning() << "[ExternalMedia] Unknown command:" << command;
        return false;
    }

    QDBusInterface player(QStringLiteral("org.bluez"),
                          m_linuxPlayerPath,
                          QStringLiteral("org.bluez.MediaPlayer1"),
                          QDBusConnection::systemBus());
    if (!player.isValid()) {
        probeSystemSession();
        return false;
    }

    const QDBusMessage reply = player.call(method);
    probeSystemSession();
    return reply.type() != QDBusMessage::ErrorMessage;
#else
    Q_UNUSED(command)
    return false;
#endif
}

void ExternalMediaController::play()
{
    if (m_hostModeEnabled) {
        if (sendSystemCommand(QStringLiteral("play")) || m_systemSessionAvailable) {
            return;
        }
    }
    if (!m_tracks.isEmpty()) {
        if (m_index < 0) loadTrack(0, true);
        else m_player->play();
        return;
    }
    m_proxyPlaying = true;
    emit playingChanged();
}

void ExternalMediaController::pause()
{
    if (m_hostModeEnabled) {
        if (sendSystemCommand(QStringLiteral("pause")) || m_systemSessionAvailable) {
            return;
        }
    }
    if (!m_tracks.isEmpty()) {
        m_player->pause();
        return;
    }
    m_proxyPlaying = false;
    emit playingChanged();
}

void ExternalMediaController::togglePlayback()
{
    if (m_hostModeEnabled && m_systemSessionAvailable) {
        // BlueZ MediaPlayer1 does NOT have a PlayPause method.
        // Determine current state and send the correct command.
        if (m_systemPlaying) {
            sendSystemCommand(QStringLiteral("pause"));
        } else {
            sendSystemCommand(QStringLiteral("play"));
        }
        return;
    }
    if (!m_tracks.isEmpty()) {
        if (playing()) pause();
        else play();
        return;
    }
    m_proxyPlaying = !m_proxyPlaying;
    emit playingChanged();
}

void ExternalMediaController::next()
{
    if (m_hostModeEnabled) {
        if (sendSystemCommand(QStringLiteral("next")) || m_systemSessionAvailable) {
            return;
        }
    }
    if (!m_tracks.isEmpty()) {
        loadTrack(m_index + 1, true);
    }
}

void ExternalMediaController::previous()
{
    if (m_hostModeEnabled) {
        if (sendSystemCommand(QStringLiteral("previous")) || m_systemSessionAvailable) {
            return;
        }
    }
    if (!m_tracks.isEmpty()) {
        loadTrack(m_index - 1, true);
    }
}

void ExternalMediaController::rescan()
{
    const bool oldAvailable = available();
    m_tracks = scanTracks();
    if (oldAvailable != available()) {
        emit availableChanged();
    }

    if (m_tracks.isEmpty()) {
        m_player->stop();
        m_index = -1;
        emitTrackMetaChanged();
        return;
    }

    if (m_index < 0 || m_index >= m_tracks.size()) {
        loadTrack(0, false);
    }
}

void ExternalMediaController::handleBluetoothDeviceConnectionChanged(const QString &address, bool connected)
{
    Q_UNUSED(address)
#if defined(Q_OS_LINUX)
    m_linuxNoPathPollCounter = 0;
    m_linuxLastRealtimeEventMs = 0;
#endif
    probeSystemSession();
#if defined(Q_OS_LINUX)
    if (connected) {
        scheduleLinuxDeferredProbes({250, 700, 1500});
    } else {
        scheduleLinuxDeferredProbes({300, 900});
    }
#else
    Q_UNUSED(connected)
#endif
}

#if defined(Q_OS_LINUX)
void ExternalMediaController::disconnectPlayerSignals()
{
    if (m_linuxPlayerPathConnected.isEmpty()) {
        return;
    }
    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.bluez"),
        m_linuxPlayerPathConnected,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onPlayerPropertiesChanged(QString,QVariantMap,QStringList)));
    qDebug() << "[ExternalMedia] Disconnected signals from" << m_linuxPlayerPathConnected;
    m_linuxPlayerPathConnected.clear();
}

void ExternalMediaController::connectPlayerSignals()
{
    if (m_linuxPlayerPath.isEmpty() || m_linuxPlayerPath == m_linuxPlayerPathConnected) {
        return;
    }
    // Disconnect previous if different
    disconnectPlayerSignals();

    const bool ok = QDBusConnection::systemBus().connect(
        QStringLiteral("org.bluez"),
        m_linuxPlayerPath,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onPlayerPropertiesChanged(QString,QVariantMap,QStringList)));

    if (ok) {
        m_linuxPlayerPathConnected = m_linuxPlayerPath;
        m_linuxLastRealtimeEventMs = QDateTime::currentMSecsSinceEpoch();
        qDebug() << "[ExternalMedia] Subscribed to PropertiesChanged on" << m_linuxPlayerPath;
    } else {
        qWarning() << "[ExternalMedia] Failed to subscribe PropertiesChanged on" << m_linuxPlayerPath;
    }
}

void ExternalMediaController::pollLinuxPlayerSnapshot()
{
    if (m_linuxPlayerPath.isEmpty()) {
        probeSystemSession();
        return;
    }

    QDBusInterface propsIface(QStringLiteral("org.bluez"),
                              m_linuxPlayerPath,
                              QStringLiteral("org.freedesktop.DBus.Properties"),
                              QDBusConnection::systemBus());
    propsIface.setTimeout(220);
    if (!propsIface.isValid()) {
        m_linuxPlayerPath.clear();
        probeSystemSession();
        return;
    }

    const QDBusMessage reply = propsIface.call(
        QStringLiteral("GetAll"),
        QStringLiteral("org.bluez.MediaPlayer1"));
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
        m_linuxPlayerPath.clear();
        probeSystemSession();
        return;
    }

    QVariantMap allProps;
    const QVariant arg = reply.arguments().constFirst();
    if (arg.canConvert<QDBusArgument>()) {
        arg.value<QDBusArgument>() >> allProps;
    } else {
        allProps = arg.toMap();
    }

    const QString status = unwrapDBusVariant(allProps.value(QStringLiteral("Status"))).toString();
    QString title;
    QString artist;

    if (allProps.contains(QStringLiteral("Track"))) {
        const QVariant trackUnwrapped = unwrapDBusVariant(allProps.value(QStringLiteral("Track")));
        QVariantMap track;
        if (trackUnwrapped.canConvert<QDBusArgument>()) {
            trackUnwrapped.value<QDBusArgument>() >> track;
        } else {
            track = trackUnwrapped.toMap();
        }

        QVariantMap normalizedTrack;
        for (auto it = track.cbegin(); it != track.cend(); ++it) {
            normalizedTrack.insert(it.key(), unwrapDBusVariant(it.value()));
        }
        title = normalizedTrack.value(QStringLiteral("Title")).toString();
        artist = trackArtistFromVariant(normalizedTrack.value(QStringLiteral("Artist")));
    }

    const bool isPlaying = status.compare(QStringLiteral("playing"), Qt::CaseInsensitive) == 0;
    setSystemSessionState(true, isPlaying, title, artist);
    m_linuxLastRealtimeEventMs = QDateTime::currentMSecsSinceEpoch();
    connectPlayerSignals();
}

void ExternalMediaController::scheduleLinuxDeferredProbes(const QList<int> &delaysMs)
{
    for (const int delayMs : delaysMs) {
        QTimer::singleShot(qMax(0, delayMs), this, [this]() {
            if (!m_hostModeEnabled) {
                return;
            }
            if (m_linuxPlayerPath.isEmpty()) {
                probeSystemSession();
            } else {
                pollLinuxPlayerSnapshot();
            }
        });
    }
}

void ExternalMediaController::subscribeBluezSignals()
{
    /* Subscribe to BlueZ ObjectManager signals for reactive Bluetooth detection.
     * InterfacesAdded fires when a new Bluetooth media player connects.
     * InterfacesRemoved fires when a Bluetooth device disconnects. */
    QDBusConnection::systemBus().connect(
        QStringLiteral("org.bluez"),
        QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesAdded"),
        this,
        SLOT(onBluezInterfacesAdded(QDBusObjectPath,QVariantMap)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.bluez"),
        QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesRemoved"),
        this,
        SLOT(onBluezInterfacesRemoved(QDBusObjectPath,QStringList)));

    qDebug() << "[ExternalMedia] Subscribed to BlueZ InterfacesAdded/Removed signals";
}

void ExternalMediaController::onBluezInterfacesAdded(
    const QDBusObjectPath &objectPath,
    const QVariantMap &interfaces)
{
    const QString path = objectPath.path();
    const bool mediaInterfaceAdded =
        interfaces.contains(QStringLiteral("org.bluez.MediaPlayer1")) ||
        interfaces.contains(QStringLiteral("org.bluez.MediaControl1"));
    const bool playerPathHint =
        path.contains(QStringLiteral("player"), Qt::CaseInsensitive);
    if (mediaInterfaceAdded || playerPathHint) {
        qDebug() << "[ExternalMedia] BlueZ interface added:" << path;
        probeSystemSession();
    }
}

void ExternalMediaController::onBluezInterfacesRemoved(
    const QDBusObjectPath &objectPath,
    const QStringList &interfaces)
{
    const QString path = objectPath.path();
    const bool mediaInterfaceRemoved =
        interfaces.contains(QStringLiteral("org.bluez.MediaPlayer1")) ||
        interfaces.contains(QStringLiteral("org.bluez.MediaControl1"));
    const bool playerPathHint =
        path.contains(QStringLiteral("player"), Qt::CaseInsensitive);
    if (mediaInterfaceRemoved || playerPathHint) {
        qDebug() << "[ExternalMedia] BlueZ interface removed:" << path;
        setSystemSessionState(false, false, QString(), QString());
    }
}

void ExternalMediaController::onPlayerPropertiesChanged(
    const QString &interface,
    const QVariantMap &changedProps,
    const QStringList &invalidated)
{
    if (interface != QStringLiteral("org.bluez.MediaPlayer1")) {
        return;
    }

    qDebug() << "[ExternalMedia] PropertiesChanged keys:" << changedProps.keys()
             << "invalidated:" << invalidated;

    bool changed = false;
    m_linuxLastRealtimeEventMs = QDateTime::currentMSecsSinceEpoch();
    if (!m_systemSessionAvailable) {
        m_systemSessionAvailable = true;
        emit availableChanged();
        changed = true;
    }

    // ---------- Status (from changedProps) ----------
    if (changedProps.contains(QStringLiteral("Status"))) {
        const QString status = unwrapDBusVariant(changedProps.value(QStringLiteral("Status"))).toString();
        const bool isPlaying = status.compare(QStringLiteral("playing"), Qt::CaseInsensitive) == 0;
        if (m_systemPlaying != isPlaying) {
            m_systemPlaying = isPlaying;
            emit playingChanged();
            changed = true;
        }
        qDebug() << "[ExternalMedia] Status changed:" << status;
    }

    // ---------- Track (from changedProps — some devices send it here) ----------
    if (changedProps.contains(QStringLiteral("Track"))) {
        const QVariant trackUnwrapped = unwrapDBusVariant(changedProps.value(QStringLiteral("Track")));
        QVariantMap track;

        if (trackUnwrapped.canConvert<QDBusArgument>()) {
            const QDBusArgument trackArg = trackUnwrapped.value<QDBusArgument>();
            trackArg >> track;
        } else {
            track = trackUnwrapped.toMap();
        }

        QVariantMap unwrappedTrack;
        for (auto it = track.cbegin(); it != track.cend(); ++it) {
            unwrappedTrack.insert(it.key(), unwrapDBusVariant(it.value()));
        }

        qDebug() << "[ExternalMedia] Track from changedProps:" << unwrappedTrack;
        const QString title = unwrappedTrack.value(QStringLiteral("Title")).toString().trimmed();
        const QString artist = trackArtistFromVariant(unwrappedTrack.value(QStringLiteral("Artist"))).trimmed();

        if (m_systemSong != title) { m_systemSong = title; emit currentSongChanged(); changed = true; }
        if (m_systemArtist != artist) { m_systemArtist = artist; emit currentArtistChanged(); changed = true; }
    }

    // ---------- Track INVALIDATED (iPhone/AVRCP sends Track in invalidated list) ----------
    // When Track is in the invalidated list, we must re-fetch it via Properties.GetAll
    // because Properties.Get("Track") often returns "No such property" on iPhone
    if (invalidated.contains(QStringLiteral("Track")) ||
        invalidated.contains(QStringLiteral("Status"))) {

        qDebug() << "[ExternalMedia] Invalidated properties detected, re-fetching via GetAll...";

        // Use the connected path as fallback: m_linuxPlayerPath may be empty if a
        // setSystemSessionState(false,...) call cleared it while the signal subscription
        // (on m_linuxPlayerPathConnected) is still active.
        const QString fetchPath = m_linuxPlayerPath.isEmpty()
                                  ? m_linuxPlayerPathConnected
                                  : m_linuxPlayerPath;

        if (fetchPath.isEmpty()) {
            qWarning() << "[ExternalMedia] No player path available for GetAll re-fetch, skipping.";
            return;
        }

        // Ensure m_linuxPlayerPath stays consistent for subsequent polls
        if (m_linuxPlayerPath.isEmpty()) {
            m_linuxPlayerPath = m_linuxPlayerPathConnected;
        }

        QDBusInterface propsIface(QStringLiteral("org.bluez"),
                                  fetchPath,
                                  QStringLiteral("org.freedesktop.DBus.Properties"),
                                  QDBusConnection::systemBus());
        if (propsIface.isValid()) {
            const QDBusMessage reply = propsIface.call(
                QStringLiteral("GetAll"),
                QStringLiteral("org.bluez.MediaPlayer1"));

            if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
                // GetAll returns a{sv}
                QVariantMap allProps;
                const QVariant arg = reply.arguments().constFirst();
                if (arg.canConvert<QDBusArgument>()) {
                    arg.value<QDBusArgument>() >> allProps;
                } else {
                    allProps = arg.toMap();
                }

                // --- Status ---
                if (invalidated.contains(QStringLiteral("Status")) &&
                    allProps.contains(QStringLiteral("Status"))) {
                    const QString status = unwrapDBusVariant(allProps.value(QStringLiteral("Status"))).toString();
                    const bool isPlaying = status.compare(QStringLiteral("playing"), Qt::CaseInsensitive) == 0;
                    if (m_systemPlaying != isPlaying) {
                        m_systemPlaying = isPlaying;
                        emit playingChanged();
                        changed = true;
                    }
                    qDebug() << "[ExternalMedia] Re-fetched Status:" << status;
                }

                // --- Track ---
                if (allProps.contains(QStringLiteral("Track"))) {
                    const QVariant trackUnwrapped = unwrapDBusVariant(allProps.value(QStringLiteral("Track")));
                    QVariantMap track;
                    if (trackUnwrapped.canConvert<QDBusArgument>()) {
                        trackUnwrapped.value<QDBusArgument>() >> track;
                    } else {
                        track = trackUnwrapped.toMap();
                    }

                    QVariantMap unwrappedTrack;
                    for (auto it = track.cbegin(); it != track.cend(); ++it) {
                        unwrappedTrack.insert(it.key(), unwrapDBusVariant(it.value()));
                    }

                    qDebug() << "[ExternalMedia] Re-fetched Track:" << unwrappedTrack;

                    const QString title = unwrappedTrack.value(QStringLiteral("Title")).toString().trimmed();
                    const QString artist = trackArtistFromVariant(unwrappedTrack.value(QStringLiteral("Artist"))).trimmed();

                    qDebug() << "[ExternalMedia] Re-fetched Title:" << title << "Artist:" << artist;

                    if (m_systemSong != title) { m_systemSong = title; emit currentSongChanged(); changed = true; }
                    if (m_systemArtist != artist) { m_systemArtist = artist; emit currentArtistChanged(); changed = true; }
                } else {
                    qDebug() << "[ExternalMedia] GetAll did not contain Track property";
                    // Track was invalidated and not yet available — schedule a delayed retry
                    QTimer::singleShot(500, this, [this]() {
                        qDebug() << "[ExternalMedia] Delayed Track re-fetch...";
                        probeSystemSession();
                    });
                }
            } else {
                qDebug() << "[ExternalMedia] GetAll failed:" << reply.errorMessage();
            }
        }
    }

    // ---------- Position ----------
    if (changedProps.contains(QStringLiteral("Position"))) {
        const uint pos = unwrapDBusVariant(changedProps.value(QStringLiteral("Position"))).toUInt();
        qDebug() << "[ExternalMedia] Position:" << pos << "ms";
    }

    if (changed) {
        qDebug() << "[ExternalMedia] Updated → Song:" << m_systemSong
                 << "Artist:" << m_systemArtist
                 << "Playing:" << m_systemPlaying;
    }
}
#endif
