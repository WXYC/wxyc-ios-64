//
//  Playcut+Stub.swift
//  Playlist
//
//  Test helper for creating Playcut instances with sensible defaults.
//
//  Created by Claude on 01/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@testable import Playlist

extension Playcut {
    /// Creates a Playcut with sensible defaults for testing.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to 1.
    ///   - hour: Hour timestamp in milliseconds since epoch. Defaults to 1000.
    ///   - chronOrderID: Chronological order ID. Defaults to matching `id`.
    ///   - timeCreated: Creation timestamp in milliseconds since epoch. Defaults to matching `hour`.
    ///   - songTitle: Song title. Defaults to "Test Song".
    ///   - labelName: Record label name. Defaults to nil.
    ///   - artistName: Artist name. Defaults to "Test Artist".
    ///   - releaseTitle: Album/release title. Defaults to "Test Album".
    ///   - rotation: Whether this is a rotation play. Defaults to false.
    static func stub(
        id: UInt64 = 1,
        hour: UInt64 = 1000,
        chronOrderID: UInt64? = nil,
        timeCreated: UInt64? = nil,
        songTitle: String = "Test Song",
        labelName: String? = nil,
        artistName: String = "Test Artist",
        releaseTitle: String? = "Test Album",
        rotation: Bool = false
    ) -> Playcut {
        Playcut(
            id: id,
            hour: hour,
            chronOrderID: chronOrderID ?? id,
            timeCreated: timeCreated ?? hour,
            songTitle: songTitle,
            labelName: labelName,
            artistName: artistName,
            releaseTitle: releaseTitle,
            rotation: rotation
        )
    }
}

extension Breakpoint {
    /// Creates a Breakpoint with sensible defaults for testing.
    static func stub(
        id: UInt64 = 1,
        hour: UInt64 = 1000,
        chronOrderID: UInt64? = nil,
        timeCreated: UInt64? = nil
    ) -> Breakpoint {
        Breakpoint(
            id: id,
            hour: hour,
            chronOrderID: chronOrderID ?? id,
            timeCreated: timeCreated ?? hour
        )
    }
}

extension Talkset {
    /// Creates a Talkset with sensible defaults for testing.
    static func stub(
        id: UInt64 = 1,
        hour: UInt64 = 1000,
        chronOrderID: UInt64? = nil,
        timeCreated: UInt64? = nil
    ) -> Talkset {
        Talkset(
            id: id,
            hour: hour,
            chronOrderID: chronOrderID ?? id,
            timeCreated: timeCreated ?? hour
        )
    }
}

extension Playlist {
    /// Creates an empty Playlist for testing.
    static func stub(
        playcuts: [Playcut] = [],
        breakpoints: [Breakpoint] = [],
        talksets: [Talkset] = []
    ) -> Playlist {
        Playlist(
            playcuts: playcuts,
            breakpoints: breakpoints,
            talksets: talksets
        )
    }
}
