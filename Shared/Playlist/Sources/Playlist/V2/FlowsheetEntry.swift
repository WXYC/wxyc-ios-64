//
//  FlowsheetEntry.swift
//  Playlist
//
//  Raw response model for API v2 flowsheet entries.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Wrapper for the v2 flowsheet API response, which nests entries under an `"entries"` key.
struct FlowsheetResponse: Codable, Sendable {
    let entries: [FlowsheetEntry]
}

/// Raw response model for a single entry from the v2 flowsheet API.
///
/// Entry type is determined by the `entry_type` field (`"track"`, `"talkset"`,
/// `"breakpoint"`, `"show_start"`, `"show_end"`). The older `message`-based
/// detection is used as a fallback when `entry_type` is absent.
struct FlowsheetEntry: Codable, Sendable {
    let id: Int
    let show_id: Int?
    let album_id: Int?
    let artist_name: String?
    let album_title: String?
    let track_title: String?
    let record_label: String?
    let rotation_id: Int?
    let rotation_play_freq: String?
    let request_flag: Bool?
    let message: String?
    let play_order: Int
    let add_time: String

    /// Explicit entry type from the v2 API (e.g. `"track"`, `"talkset"`, `"breakpoint"`,
    /// `"show_start"`, `"show_end"`). `nil` when decoding older response formats.
    var entry_type: String? = nil

    /// DJ name for show start/end markers. Present only in v2 responses.
    var dj_name: String? = nil

    // Metadata fields from album_metadata/artist_metadata LEFT JOINs.
    // Present only in v2 responses after backend enrichment completes.
    // Defaults to nil so existing test constructors remain valid.
    var artwork_url: String? = nil
    var discogs_url: String? = nil
    var release_year: Int? = nil
    var spotify_url: String? = nil
    var apple_music_url: String? = nil
    var youtube_music_url: String? = nil
    var bandcamp_url: String? = nil
    var soundcloud_url: String? = nil
    var artist_bio: String? = nil
    var artist_wikipedia_url: String? = nil
}
