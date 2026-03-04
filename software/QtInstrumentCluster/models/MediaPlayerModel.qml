pragma Singleton
import QtQuick 2.15
import MainModel 1.0

QtObject {
    id: mediaplayermodel
    property bool mediaPlayback: true

    function play() {
        mediaplayermodel.mediaPlayback = true
    }
    function stop() {
        mediaplayermodel.mediaPlayback = false
    }
    function togglePlayback() {
        if (mediaPlayback) stop()
        else play()
    }
    function nextSong() {
        track = (track + 1) % trackCount
    }
    function previousSong() {
        track = (track + trackCount - 1) % trackCount
    }

    property int track: 0
    property int timePassed: 0 // sec
    readonly property int trackCount: 5
    readonly property int changeSongDuration: 300

    /* Track metadata */
    readonly property var tracks: [
        { artist: "Thomas Lammer",        song: "Setsuna",     duration: 210 },
        { artist: "Thievery Corporation", song: "Le Monde",    duration: 228 },
        { artist: "Tycho",                song: "Awake",       duration: 192 },
        { artist: "De Phazz",             song: "Chocolate",   duration: 245 },
        { artist: "AK",                   song: "Discovery",   duration: 270 }
    ]

    readonly property string currentArtist: tracks[track].artist
    readonly property string currentSong: tracks[track].song
    readonly property int currentDuration: tracks[track].duration
    readonly property real progress: currentDuration > 0 ? Math.min(timePassed / currentDuration, 1.0) : 0

    /* Format seconds to M:SS */
    function formatTime(secs) {
        var m = Math.floor(secs / 60)
        var s = Math.floor(secs % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    readonly property string timePassedText: formatTime(timePassed)
    readonly property string timeRemainingText: "-" + formatTime(Math.max(0, currentDuration - timePassed))

    onTrackChanged: {
        timePassed = 0
    }

    onTimePassedChanged: {
        if (timePassed > currentDuration) {
            nextSong()
        }
    }

    property Timer timePassedTimer: Timer {
        running: MainModel.simulationRunning && mediaplayermodel.mediaPlayback
        repeat: true
        interval: 1000
        onTriggered: { timePassed += 1 }
    }
}
