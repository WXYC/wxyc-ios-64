//
//  FlowsheetEntry+Fixture.swift
//  Playlist
//
//  Shared wire-row fixture builder for converter and timeline tests. Building
//  fixtures from wire rows (rather than stubs carrying a pre-computed
//  chronOrderID) is what makes ordering tests probative: a dj-site reorder IS
//  a play_order change, and a stub with a hand-written key would pass on
//  either side of #839.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

@testable import Playlist

extension FlowsheetEntry {
    /// A minimal wire row with WXYC-canonical track defaults
    /// (`docs/test-fixtures.md`).
    ///
    /// Track-content fields are applied only to `entry_type == "track"` rows —
    /// talksets, breakpoints, and show markers carry none on the real feed.
    /// `FlowsheetEntry` gains required fields over time; keeping the memberwise
    /// init in this one place means a new field is one edit here, not one per
    /// hand-rolled fixture.
    static func fixture(
        id: Int,
        showID: Int? = 42,
        playOrder: Int,
        entryType: String = "track",
        artistName: String? = "Stereolab",
        albumTitle: String? = "Aluminum Tunes",
        trackTitle: String? = "Pack Yr Romantic Mind",
        recordLabel: String? = "Duophonic",
        message: String? = nil,
        addTime: String = "2026-07-31T18:00:00Z"
    ) -> FlowsheetEntry {
        let isTrack = entryType == "track"
        return FlowsheetEntry(
            id: id,
            show_id: showID,
            album_id: nil,
            artist_name: isTrack ? artistName : nil,
            album_title: isTrack ? albumTitle : nil,
            track_title: isTrack ? trackTitle : nil,
            record_label: isTrack ? recordLabel : nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: isTrack ? false : nil,
            message: message,
            play_order: playOrder,
            add_time: addTime,
            entry_type: entryType
        )
    }
}
