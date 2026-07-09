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

extension ShowMarker {
    /// Creates a ShowMarker with sensible defaults for testing.
    ///
    /// Defaults to a sign-on with no DJ name. Pass `isStart: false` for a sign-off.
    public static func stub(
        id: UInt64 = 1,
        hour: UInt64 = 1000,
        chronOrderID: UInt64? = nil,
        timeCreated: UInt64? = nil,
        isStart: Bool = true,
        djName: String? = nil,
        message: String = "Start of show"
    ) -> ShowMarker {
        ShowMarker(
            id: id,
            hour: hour,
            chronOrderID: chronOrderID ?? id,
            timeCreated: timeCreated ?? hour,
            isStart: isStart,
            djName: djName,
            message: message
        )
    }
}

extension UpcomingShow {
    /// A fixed, deterministic default date (2026-08-01, station zone) for stubs.
    ///
    /// Built inline rather than via the model's internal `dateParser`, which is
    /// not visible from this separate `PlaylistTesting` module. Falls back to a
    /// fixed epoch offset so the helper stays force-unwrap-free.
    private static let defaultDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let components = DateComponents(year: 2026, month: 8, day: 1)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_785_898_800)
    }()

    /// Creates an `UpcomingShow` with sensible defaults for testing.
    ///
    /// Defaults use a WXYC-canonical touring artist (Jessica Pratt at Cat's
    /// Cradle) rather than placeholder strings. See `docs/test-fixtures.md`.
    public static func stub(
        id: Int = 4821,
        eventName: String = "Jessica Pratt",
        artist: String? = "Jessica Pratt",
        supportArtists: String? = "Julie Byrne",
        venueName: String? = "Cat's Cradle",
        venueCity: String? = "Carrboro",
        venueColorHex: String? = "#B34876",
        date: Date? = nil,
        doorsTime: String? = "19:00:00",
        showTime: String? = "20:00:00",
        status: ShowStatus = .onSale,
        priceMin: Double? = 22.0,
        priceMax: Double? = 25.0,
        ticketURL: URL? = URL(string: "https://www.etix.com/ticket/p/jessica-pratt"),
        sourceURL: URL? = URL(string: "https://catscradle.com/event/jessica-pratt"),
        imageURL: URL? = nil,
        ageRestriction: String? = "All Ages"
    ) -> UpcomingShow {
        UpcomingShow(
            id: id,
            eventName: eventName,
            artist: artist,
            supportArtists: supportArtists,
            venueName: venueName,
            venueCity: venueCity,
            venueColorHex: venueColorHex,
            date: date ?? defaultDate,
            doorsTime: doorsTime,
            showTime: showTime,
            status: status,
            priceMin: priceMin,
            priceMax: priceMax,
            ticketURL: ticketURL,
            sourceURL: sourceURL,
            imageURL: imageURL,
            ageRestriction: ageRestriction
        )
    }
}

extension Playlist {
    /// Creates a Playlist stub for testing.
    public static func stub(
        playcuts: [Playcut] = [],
        breakpoints: [Breakpoint] = [],
        talksets: [Talkset] = [],
        showMarkers: [ShowMarker] = [],
        onAir: OnAir = .unknown
    ) -> Playlist {
        Playlist(
            playcuts: playcuts,
            breakpoints: breakpoints,
            talksets: talksets,
            showMarkers: showMarkers,
            onAir: onAir
        )
    }
}
