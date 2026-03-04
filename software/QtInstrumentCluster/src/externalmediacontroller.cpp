#include "externalmediacontroller.h"

#include <QAudioOutput>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMediaMetaData>
#include <QMediaPlayer>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

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
    , m_audioOutput(new QAudioOutput(this))
    , m_probeProcess(new QProcess(this))
    , m_probeTimer(new QTimer(this))
    , m_index(-1)
    , m_hostModeEnabled(true)
    , m_proxyPlaying(false)
    , m_systemSessionAvailable(false)
    , m_systemPlaying(false)
{
    m_audioOutput->setVolume(1.0);
    m_player->setAudioOutput(m_audioOutput);

    connect(m_player, &QMediaPlayer::playbackStateChanged, this, &ExternalMediaController::playingChanged);
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus status) {
        if (status == QMediaPlayer::EndOfMedia) {
            next();
        }
    });
    connect(m_player, &QMediaPlayer::metaDataChanged, this, [this]() {
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

    m_probeTimer->setInterval(1200);
    connect(m_probeTimer, &QTimer::timeout, this, &ExternalMediaController::probeSystemSession);
    m_probeTimer->start();

    rescan();
    probeSystemSession();
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
        return m_player->playbackState() == QMediaPlayer::PlayingState;
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

    const QString metaTitle = m_player->metaData().value(QMediaMetaData::Title).toString();
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

    const QString metaArtist = m_player->metaData().value(QMediaMetaData::ContributingArtist).toStringList().join(", ");
    if (!metaArtist.isEmpty()) {
        return metaArtist;
    }
    if (!m_tracks.isEmpty()) {
        return QStringLiteral("Host media");
    }
    return QString();
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
    m_player->setSource(QUrl::fromLocalFile(m_tracks[m_index]));
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
    if (m_probeProcess->state() != QProcess::NotRunning) {
        return;
    }
    m_probeProcess->start(QStringLiteral("powershell"),
                          {QStringLiteral("-NoProfile"),
                           QStringLiteral("-ExecutionPolicy"), QStringLiteral("Bypass"),
                           QStringLiteral("-Command"), sessionProbeScript()});
}

void ExternalMediaController::applySystemSessionPayload(const QString &jsonPayload)
{
    if (jsonPayload.isEmpty()) {
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return;
    }

    const QJsonObject obj = doc.object();
    const bool oldAvailable = m_systemSessionAvailable;
    const bool oldPlaying = m_systemPlaying;
    const QString oldSong = m_systemSong;
    const QString oldArtist = m_systemArtist;

    m_systemSessionAvailable = obj.value(QStringLiteral("available")).toBool(false);
    if (!m_systemSessionAvailable) {
        m_systemPlaying = false;
        m_systemSong.clear();
        m_systemArtist.clear();
    } else {
        m_systemSong = obj.value(QStringLiteral("title")).toString();
        m_systemArtist = obj.value(QStringLiteral("artist")).toString();
        const QString status = obj.value(QStringLiteral("status")).toString();
        m_systemPlaying = status.compare(QStringLiteral("Playing"), Qt::CaseInsensitive) == 0;
    }

    if (oldAvailable != m_systemSessionAvailable) emit availableChanged();
    if (oldPlaying != m_systemPlaying) emit playingChanged();
    if (oldSong != m_systemSong) emit currentSongChanged();
    if (oldArtist != m_systemArtist) emit currentArtistChanged();
}

bool ExternalMediaController::sendSystemCommand(const QString &command)
{
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
}

void ExternalMediaController::play()
{
    if (m_hostModeEnabled && sendSystemCommand(QStringLiteral("play"))) {
        return;
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
    if (m_hostModeEnabled && sendSystemCommand(QStringLiteral("pause"))) {
        return;
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
    if (m_hostModeEnabled && sendSystemCommand(QStringLiteral("toggle"))) {
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
    if (m_hostModeEnabled && sendSystemCommand(QStringLiteral("next"))) {
        return;
    }
    if (!m_tracks.isEmpty()) {
        loadTrack(m_index + 1, true);
    }
}

void ExternalMediaController::previous()
{
    if (m_hostModeEnabled && sendSystemCommand(QStringLiteral("previous"))) {
        return;
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
