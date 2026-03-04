pragma Singleton
import QtQuick 2.15
import ExternalMedia 1.0

QtObject {
    id: mediaplayermodel

    readonly property string modeLabel: "External"
    readonly property bool mediaPlayback: ExternalMedia.playing
    readonly property int changeSongDuration: 300

    readonly property string currentArtist: ExternalMedia.currentArtist.length > 0
                                           ? ExternalMedia.currentArtist
                                           : "Bluetooth device"
    readonly property string currentSong: ExternalMedia.currentSong.length > 0
                                         ? ExternalMedia.currentSong
                                         : "No media"

    function play() {
        ExternalMedia.play()
    }

    function stop() {
        ExternalMedia.pause()
    }

    function togglePlayback() {
        ExternalMedia.togglePlayback()
    }

    function nextSong() {
        ExternalMedia.next()
    }

    function previousSong() {
        ExternalMedia.previous()
    }
}
