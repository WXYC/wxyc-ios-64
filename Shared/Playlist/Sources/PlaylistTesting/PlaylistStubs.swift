//
//  PlaylistStubs.swift
//  PlaylistTesting
//
//  Convenience stub factories for Playcut, Playlist, Breakpoint, and Talkset.
//  Centralizes the test stub extensions that were duplicated across test targets.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

extension Playcut {
    /// Creates a Playcut with sensible defaults for testing.
    ///
    /// Defaults use a WXYC-canonical track (Juana Molina — "la paradoja" from DOGA) rather
    /// than generic placeholder strings. See `docs/test-fixtures.md` for the example pool.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to 1.
    ///   - hour: Hour timestamp in milliseconds since epoch. Defaults to 1000.
    ///   - chronOrderID: Chronological order ID. Defaults to matching `id`.
    ///   - timeCreated: Creation timestamp in milliseconds since epoch. Defaults to matching `hour`.
    ///   - songTitle: Song title. Defaults to "la paradoja".
    ///   - labelName: Record label name. Defaults to nil.
    ///   - artistName: Artist name. Defaults to "Juana Molina".
    ///   - releaseTitle: Album/release title. Defaults to "DOGA".
    ///   - rotation: Whether this is a rotation play. Defaults to false.
    ///   - artworkURL: Optional artwork URL. Defaults to nil.
    ///   - genres: Optional Discogs genre classifications. Defaults to nil.
    ///   - styles: Optional Discogs style classifications. Defaults to nil.
    public static func stub(
        id: UInt64 = 1,
        hour: UInt64 = 1000,
        chronOrderID: UInt64? = nil,
        timeCreated: UInt64? = nil,
        songTitle: String = "la paradoja",
        labelName: String? = nil,
        artistName: String = "Juana Molina",
        releaseTitle: String? = "DOGA",
        rotation: Bool = false,
        artworkURL: URL? = nil,
        genres: [String]? = nil,
        styles: [String]? = nil
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
            rotation: rotation,
            artworkURL: artworkURL,
            genres: genres,
            styles: styles
        )
    }
}

extension Breakpoint {
    /// Creates a Breakpoint with sensible defaults for testing.
    public static func stub(
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
    public static func stub(
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
    /// Creates a Playlist stub for testing.
    public static func stub(
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
