pragma Singleton
import QtQuick 2.15
import MainModel 1.0
import ExternalMedia 1.0

QtObject {
    id: mediaplayermodel

    // External mode models "BT speaker" behavior: audio comes from system Bluetooth sink.
    readonly property bool externalMode: ExternalMedia.hostModeEnabled
    readonly property string modeLabel: externalMode ? "External" : "Simulation"

    property bool simMediaPlayback: true
    readonly property bool mediaPlayback: externalMode ? ExternalMedia.playing : simMediaPlayback

    function play() {
        if (externalMode) ExternalMedia.play()
        else simMediaPlayback = true
    }

    function stop() {
        if (externalMode) ExternalMedia.pause()
        else simMediaPlayback = false
    }

    function togglePlayback() {
        if (externalMode) ExternalMedia.togglePlayback()
        else simMediaPlayback = !simMediaPlayback
    }

    function nextSong() {
        if (externalMode) ExternalMedia.next()
        else track = (track + 1) % trackCount
    }

    function previousSong() {
        if (externalMode) ExternalMedia.previous()
        else track = (track + trackCount - 1) % trackCount
    }

    property int track: 0
    property int timePassed: 0
    readonly property int trackCount: 5
    readonly property int changeSongDuration: 300

    readonly property var tracks: [
        { artist: "Thomas Lammer",        song: "Setsuna",     duration: 210 },
        { artist: "Thievery Corporation", song: "Le Monde",    duration: 228 },
        { artist: "Tycho",                song: "Awake",       duration: 192 },
        { artist: "De Phazz",             song: "Chocolate",   duration: 245 },
        { artist: "AK",                   song: "Discovery",   duration: 270 }
    ]

    readonly property string simArtist: tracks[track].artist
    readonly property string simSong: tracks[track].song
    readonly property int simDuration: tracks[track].duration

    readonly property string externalArtistText: ExternalMedia.currentArtist.length > 0 ? ExternalMedia.currentArtist : "Bluetooth device"
    readonly property string externalSongText: ExternalMedia.currentSong.length > 0 ? ExternalMedia.currentSong : "External stream"

    readonly property string currentArtist: externalMode ? externalArtistText : simArtist
    readonly property string currentSong: externalMode ? externalSongText : simSong

    onTrackChanged: {
        timePassed = 0
    }

    onTimePassedChanged: {
        if (timePassed > simDuration) {
            nextSong()
        }
    }

    property Timer timePassedTimer: Timer {
        running: MainModel.simulationRunning && !mediaplayermodel.externalMode && mediaplayermodel.simMediaPlayback
        repeat: true
        interval: 1000
        onTriggered: { timePassed += 1 }
    }
}
