//
//  LiveRadioStationEntity.swift
//  Intents
//
//  The single WXYC live-radio station, modeled as an iOS 27 audio-schema entity
//  so "Hey Siri, play WXYC" can resolve to a station WXYC owns instead of an
//  Apple Music search.
//
//  Siri's audio search reaches the station through two queries. The documented
//  iOS 27 path is the `IntentValueQuery` at the bottom of this file: Siri
//  classifies the request into an `AudioSearch`, and "Play WXYC" — the app name
//  and nothing else — arrives as `.unspecified`. The `EntityStringQuery` only
//  ever sees a search term, so on its own it can never answer that request; on
//  iOS 27.0 the bare phrase fell through to Apple Music while "Play WXYC 89.3
//  FM" still worked, most likely because the frequency reached the string
//  query as a search term and hit its `89.3` check. The string query stays for
//  Shortcuts' text search. A `UniqueAppEntityQuery` is never consulted on
//  either path, which is why an otherwise correctly-registered station once
//  came back "I can't find the station WXYC".
//
//  The entity is titled "WXYC", not "WXYC 89.3 FM": the title is what Siri
//  says back and what the Shortcuts app shows, and the one visible shortcut is
//  "Play WXYC" (`WXYCAppShortcuts`).
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema): the schema symbols do not
//  exist in earlier SDKs. Pre-iOS-27 voice playback stays on the PlayWXYC path.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import AppIntents
import Core
import Foundation
#if canImport(MediaIntents)
import MediaIntents
#endif

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@AppEntity(schema: .audio.liveRadioStation)
struct LiveRadioStationEntity {
    static let defaultQuery = LiveRadioStationEntityQuery()

    let id: String

    var title: String
    var providerName: String?

    init() {
        self.id = RadioStation.WXYC.identifier
        self.title = RadioStation.WXYC.name
        self.providerName = "WXYC Chapel Hill"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(RadioStation.WXYC.name)")
    }

    /// Resolves the one WXYC station. `entities(matching:)` serves Shortcuts'
    /// text search, where the term is typed against every entity type the app
    /// has, so it matches only the call sign or frequency. `entities(for:)`
    /// round-trips the stable identifier so a resolved entity can be re-fetched
    /// later.
    struct LiveRadioStationEntityQuery: EntityStringQuery {
        func entities(for identifiers: [String]) async throws -> [LiveRadioStationEntity] {
            let station = LiveRadioStationEntity()
            return identifiers.contains(station.id) ? [station] : []
        }

        func entities(matching string: String) async throws -> [LiveRadioStationEntity] {
            Self.namesWXYC(string) ? [LiveRadioStationEntity()] : []
        }

        func suggestedEntities() async throws -> [LiveRadioStationEntity] {
            [LiveRadioStationEntity()]
        }

        /// Whether a Siri-transcribed term names the station by call sign or
        /// frequency. `localizedStandardContains` because the term is
        /// transcribed speech (see `docs/swift-style.md`).
        private static func namesWXYC(_ term: String) -> Bool {
            term.localizedStandardContains("WXYC") || term.localizedStandardContains("89.3")
        }

        /// Whether a link Siri was handed points at WXYC. Any `wxyc.org` host
        /// counts — the website, `hls.wxyc.org`, and the rest — so a merch or
        /// archive link also starts the live stream, which is the only thing
        /// WXYC can play. The MP3 stream sits on a host ibiblio shares with
        /// other stations, so it is matched by host and path, scheme ignored.
        private static func isWXYC(_ url: URL) -> Bool {
            guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
            if host == "wxyc.org" || host.hasSuffix(".wxyc.org") {
                return true
            }
            let stream = RadioStation.WXYC.streamURL
            return host == stream.host(percentEncoded: false)?.lowercased()
                && url.path(percentEncoded: false) == stream.path(percentEncoded: false)
        }
    }
}

#if canImport(MediaIntents)
/// The documented iOS 27 audio-search path (`MediaIntents`): Siri hands the
/// query a classified `AudioSearch` rather than a string, and consults it only
/// once it has chosen WXYC to handle the request. WXYC has exactly one thing to
/// play, so every criterion that could mean "something on WXYC" resolves to the
/// station: `.unspecified` is "Play WXYC" with nothing named — the whole
/// reason this conformance exists — and `.searchQuery` is whatever words were
/// left over ("radio", "live", a song), none of which should turn into "not
/// found". `.url` resolves links that point at WXYC and nothing else.
///
/// Lives on the entity's own query, returning the entity, the way Apple's
/// audio-search sample does; Siri resolves `PlayWXYCAudio.audioEntity` (the
/// one-case `AudioItem` union) through this member entity's query — the same
/// route the July device logs showed for the string query.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension LiveRadioStationEntity.LiveRadioStationEntityQuery: IntentValueQuery {
    func values(for search: AudioSearch) async throws -> [LiveRadioStationEntity] {
        switch search.criteria {
        case .unspecified, .searchQuery:
            return [LiveRadioStationEntity()]
        case .url(let urls):
            return urls.contains(where: Self.isWXYC) ? [LiveRadioStationEntity()] : []
        @unknown default:
            return []
        }
    }
}
#endif
#endif
#endif
