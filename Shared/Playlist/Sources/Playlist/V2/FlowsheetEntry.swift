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

/// Raw response model for a single entry from the v2 flowsheet API.
///
/// Entry type is determined by the `message` field:
/// - `nil` = playcut (regular song)
/// - `"Talkset"` = talkset
/// - Contains `"Breakpoint"` = breakpoint
/// - `"Start of Show: ..."` / `"End of Show: ..."` = show marker
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
