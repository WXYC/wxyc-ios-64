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
}
