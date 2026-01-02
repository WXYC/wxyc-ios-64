import Testing
import Foundation
@testable import Playlist

// MARK: - FlowsheetConverter Tests

@Suite("FlowsheetConverter Tests")
struct FlowsheetConverterTests {

    @Test("Converts playcut entry correctly when message is nil")
    func convertsPlaycutEntry() {
        let entry = FlowsheetEntry(
            id: 123,
            show_id: 456,
            album_id: 789,
            artist_name: "Test Artist",
            album_title: "Test Album",
            track_title: "Test Song",
            record_label: "Test Label",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 1,
            add_time: "2024-01-15T14:30:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.count == 1)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.talksets.isEmpty)
        #expect(playlist.showMarkers.isEmpty)

        let playcut = playlist.playcuts.first!
        #expect(playcut.id == 123)
        #expect(playcut.artistName == "Test Artist")
        #expect(playcut.songTitle == "Test Song")
        #expect(playcut.releaseTitle == "Test Album")
        #expect(playcut.labelName == "Test Label")
        #expect(playcut.chronOrderID == 1)
    }

    @Test("Converts talkset entry correctly when message is 'Talkset'")
    func convertsTalksetEntry() {
        let entry = FlowsheetEntry(
            id: 124,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "Talkset",
            play_order: 2,
            add_time: "2024-01-15T14:35:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.talksets.count == 1)
        #expect(playlist.playcuts.isEmpty)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.showMarkers.isEmpty)

        let talkset = playlist.talksets.first!
        #expect(talkset.id == 124)
        #expect(talkset.chronOrderID == 2)
    }

    @Test("Converts breakpoint entry correctly when message contains 'Breakpoint'")
    func convertsBreakpointEntry() {
        let entry = FlowsheetEntry(
            id: 125,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "01:00 PM Breakpoint",
            play_order: 3,
            add_time: "2024-01-15T15:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.breakpoints.count == 1)
        #expect(playlist.playcuts.isEmpty)
        #expect(playlist.talksets.isEmpty)
        #expect(playlist.showMarkers.isEmpty)

        let breakpoint = playlist.breakpoints.first!
        #expect(breakpoint.id == 125)
        #expect(breakpoint.chronOrderID == 3)
    }

    @Test("Converts show start marker correctly")
    func convertsShowStartMarker() {
        let entry = FlowsheetEntry(
            id: 126,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "Start of Show: DJ Cool joined the set at 10/14/2025 2:00 PM",
            play_order: 4,
            add_time: "2024-01-15T14:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.showMarkers.count == 1)
        #expect(playlist.playcuts.isEmpty)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.talksets.isEmpty)

        let marker = playlist.showMarkers.first!
        #expect(marker.id == 126)
        #expect(marker.isStart == true)
        #expect(marker.djName == "DJ Cool")
        #expect(marker.chronOrderID == 4)
    }

    @Test("Converts show end marker correctly")
    func convertsShowEndMarker() {
        let entry = FlowsheetEntry(
            id: 127,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "End of Show: DJ Cool left the set at 10/14/2025 4:00 PM",
            play_order: 5,
            add_time: "2024-01-15T16:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.showMarkers.count == 1)

        let marker = playlist.showMarkers.first!
        #expect(marker.id == 127)
        #expect(marker.isStart == false)
        #expect(marker.djName == "DJ Cool")
    }

    @Test("Handles missing artist and track title gracefully")
    func handlesMissingArtistAndTrack() {
        let entry = FlowsheetEntry(
            id: 128,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: nil,
            play_order: 6,
            add_time: "2024-01-15T14:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.count == 1)
        let playcut = playlist.playcuts.first!
        #expect(playcut.artistName == "Unknown")
        #expect(playcut.songTitle == "Unknown")
    }

    @Test("Parses ISO 8601 timestamp with fractional seconds correctly")
    func parsesTimestampWithFractionalSeconds() {
        let entry = FlowsheetEntry(
            id: 129,
            show_id: nil,
            album_id: nil,
            artist_name: "Artist",
            album_title: nil,
            track_title: "Song",
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: nil,
            play_order: 1,
            add_time: "2024-01-15T14:30:45.123Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        let playcut = playlist.playcuts.first!
        // 2024-01-15T14:30:45.123Z = 1705329045123 milliseconds (approximately)
        #expect(playcut.hour > 0)
    }

    @Test("Parses ISO 8601 timestamp without fractional seconds correctly")
    func parsesTimestampWithoutFractionalSeconds() {
        let entry = FlowsheetEntry(
            id: 130,
            show_id: nil,
            album_id: nil,
            artist_name: "Artist",
            album_title: nil,
            track_title: "Song",
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: nil,
            play_order: 1,
            add_time: "2024-01-15T14:30:45Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        let playcut = playlist.playcuts.first!
        #expect(playcut.hour > 0)
    }

    @Test("Converts multiple entries of different types")
    func convertsMultipleEntryTypes() {
        let entries = [
            FlowsheetEntry(
                id: 1, show_id: nil, album_id: nil,
                artist_name: "Artist", album_title: "Album", track_title: "Song",
                record_label: "Label", rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: nil, play_order: 1,
                add_time: "2024-01-15T14:00:00Z"
            ),
            FlowsheetEntry(
                id: 2, show_id: nil, album_id: nil,
                artist_name: nil, album_title: nil, track_title: nil,
                record_label: nil, rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: "Talkset", play_order: 2,
                add_time: "2024-01-15T14:05:00Z"
            ),
            FlowsheetEntry(
                id: 3, show_id: nil, album_id: nil,
                artist_name: nil, album_title: nil, track_title: nil,
                record_label: nil, rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: "2:00 PM Breakpoint", play_order: 3,
                add_time: "2024-01-15T14:10:00Z"
            ),
            FlowsheetEntry(
                id: 4, show_id: nil, album_id: nil,
                artist_name: nil, album_title: nil, track_title: nil,
                record_label: nil, rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: "Start of Show: DJ Test joined the set at 10/14/2025",
                play_order: 4, add_time: "2024-01-15T14:15:00Z"
            )
        ]

        let playlist = FlowsheetConverter.convert(entries)

        #expect(playlist.playcuts.count == 1)
        #expect(playlist.talksets.count == 1)
        #expect(playlist.breakpoints.count == 1)
        #expect(playlist.showMarkers.count == 1)
    }
}
