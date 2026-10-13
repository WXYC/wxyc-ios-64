//
//  PlayWXYCAudioTests.swift
//  WXYCIntents
//
//  Unit coverage for the iOS 27 audio-schema intent and its station entity.
//  Siri's media-domain routing can't be exercised on a simulator, so these tests
//  prove the intent is correctly shaped and the station entity resolves; the
//  schema conformance itself is enforced by the appintentsmetadataprocessor at
//  build time, and routing is verified on-device.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import Core
import Foundation
import PlaybackCore
import Testing
@testable import WXYCIntents
#if canImport(MediaIntents)
import MediaIntents
#endif

// The IntentValueQuery under test and its tests sit behind the same
// `canImport(MediaIntents)` gate, so a missing module would drop both and the
// run would still pass. On iOS the framework ships with the 27 SDK this file
// already requires, so its absence is a build misconfiguration, not a platform.
#if os(iOS) && !canImport(MediaIntents)
#error("MediaIntents is part of the iOS 27 SDK; the audio-search tests must compile here")
#endif

@Suite("PlayWXYCAudio (iOS 27 audio schema)")
struct PlayWXYCAudioTests {
    /// Terms that name the station by call sign or frequency. The string query
    /// (Shortcuts text search) must resolve each to the one station, and so
    /// must the audio search's `.searchQuery` -- a `UniqueAppEntityQuery` left
    /// both unanswered ("I can't find the station WXYC").
    static let stationSearchTerms = ["WXYC", "wxyc", "WXYC 89.3", "WXYC 89.3 FM", "89.3 FM"]

    /// Terms that don't name the station. The string query rejects them --
    /// Shortcuts searches every entity type with the same text -- while the
    /// audio search still resolves the station, because Siri only asks once it
    /// has chosen WXYC, and WXYC has one thing to play.
    static let otherSearchTerms = ["the weather tomorrow", "WXDU", "radio", "live", "Stereolab"]

    /// Links Siri can hand the audio query as `.url` criteria that point at
    /// this station: the website, both stream URLs from `RadioStation.WXYC`,
    /// and the MP3 stream over plain http -- the scheme must not matter.
    static let stationURLStrings = [
        "https://wxyc.org",
        "https://www.wxyc.org/listen",
        RadioStation.WXYC.streamURL.absoluteString,
        RadioStation.WXYC.hlsStreamURL.absoluteString,
        "http://audio-mp3.ibiblio.org/wxyc.mp3",
    ]

    /// Links on hosts WXYC shares (ibiblio streams many stations) or has
    /// nothing to do with -- none of these may resolve to the station.
    static let foreignURLStrings = [
        "https://audio-mp3.ibiblio.org/wcpe.mp3",
        "https://music.apple.com/us/album/doga/1",
    ]

    @Test("Audio search for the station name resolves to WXYC", arguments: stationSearchTerms)
    func audioSearchResolvesStation(term: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(matching: term)

        #expect(matches.count == 1)
        #expect(matches.first?.id == "org.wxyc.live")
        #expect(matches.first?.title == "WXYC")
    }

    @Test("Text search for a term that doesn't name the station resolves nothing", arguments: otherSearchTerms)
    func textSearchIgnoresOtherTerms(term: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(matching: term)

        #expect(matches.isEmpty)
    }

    @Test("The station resolves back from its stable identifier")
    func stationResolvesByIdentifier() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(for: ["org.wxyc.live"])

        #expect(matches.count == 1)
        #expect(matches.first?.title == "WXYC")
    }

    @Test("An unknown identifier resolves to nothing")
    func unknownIdentifierResolvesNothing() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(for: ["org.example.other"])

        #expect(matches.isEmpty)
    }

    @Test("The station entity's initializer carries stable identity")
    func liveRadioStationInitializer() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let station = LiveRadioStationEntity()

        #expect(station.id == "org.wxyc.live")
        #expect(station.title == "WXYC")
    }

    @Test("The intent starts playback in the background without opening the app")
    func intentRunsInBackground() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        #expect(PlayWXYCAudio.openAppWhenRun == false)
    }

    /// Apple's documented pattern for a schema intent that sits beside an
    /// older shortcut intent (`PlayWXYC`): mark the schema one assistant-only
    /// so the pair doesn't present as duplicates. Siri still routes
    /// "Play WXYC" here; the Shortcuts app lists one Play WXYC action.
    @Test("The schema intent is assistant-only, so Shortcuts lists one Play WXYC")
    func intentIsAssistantOnly() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        #expect(PlayWXYCAudio.isAssistantOnly)
    }

    // MARK: - IntentValueQuery (the documented iOS 27 audio-search path)
    //
    // Siri's audio search hands the query an `AudioSearch`, not a bare
    // string. "Play WXYC" -- the app name and nothing else -- arrives as
    // `.unspecified`, which an `EntityStringQuery` alone can never see. That
    // gap is why the bare phrase fell through to Apple Music on iOS 27.0
    // while "Play WXYC 89.3 FM" (a `.searchQuery` with a remainder) worked.

    #if canImport(MediaIntents)
    @Test("An unspecified audio search -- \"Play WXYC\", nothing named -- resolves to the station")
    func unspecifiedSearchResolvesStation() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.values(
            for: AudioSearch(criteria: .unspecified)
        )

        #expect(matches.count == 1)
        #expect(matches.first?.id == "org.wxyc.live")
    }

    @Test("A search query naming the station resolves to it", arguments: stationSearchTerms)
    func searchQueryResolvesStation(term: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.values(
            for: AudioSearch(criteria: .searchQuery(term))
        )

        #expect(matches.count == 1)
        #expect(matches.first?.id == "org.wxyc.live")
    }

    @Test("Any other search query still resolves the station -- WXYC has one thing to play", arguments: otherSearchTerms)
    func otherSearchQueryResolvesStation(term: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.values(
            for: AudioSearch(criteria: .searchQuery(term))
        )

        #expect(matches.count == 1)
        #expect(matches.first?.id == "org.wxyc.live")
    }

    @Test("A WXYC link resolves to the station", arguments: stationURLStrings)
    func stationURLResolvesStation(urlString: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let url = try #require(URL(string: urlString))

        let matches = try await LiveRadioStationEntity.defaultQuery.values(
            for: AudioSearch(criteria: .url([url]))
        )

        #expect(matches.count == 1)
        #expect(matches.first?.id == "org.wxyc.live")
    }

    @Test("A link that isn't WXYC's resolves nothing", arguments: foreignURLStrings)
    func foreignURLResolvesNothing(urlString: String) async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let url = try #require(URL(string: urlString))

        let matches = try await LiveRadioStationEntity.defaultQuery.values(
            for: AudioSearch(criteria: .url([url]))
        )

        #expect(matches.isEmpty)
    }

    @Test("A WXYC link among foreign ones still resolves the station")
    func mixedLinksResolveStation() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let foreign = try #require(URL(string: "https://audio-mp3.ibiblio.org/wcpe.mp3"))
        let station = try #require(URL(string: "https://wxyc.org"))

        let matches = try await LiveRadioStationEntity.defaultQuery.values(
            for: AudioSearch(criteria: .url([foreign, station]))
        )

        #expect(matches.count == 1)
    }
    #endif

    // MARK: - perform() (#497)
    //
    // `PlayWXYCAudio.perform()`'s entire body is
    // `await IntentPlayback.startAndAwait(reason: .playAudioSchemaIntent)`.
    // App Intents instantiates the intent itself via a non-public `init()`,
    // so a fake controller can't be injected into `perform()` directly --
    // the seam lives on `startAndAwait(reason:controller:)` instead (see
    // `IntentPlaybackTests.swift`, which covers the poll/timeout mechanics
    // generically). These two tests drive that exact call with the exact
    // reason `perform()` passes, so a regression that changed the reason or
    // dropped the await would be caught here even though `perform()` itself
    // can't be called with a fake underneath it.

    // `FakeIntentPlaybackController` and `startAndAwait` are both `@MainActor`
    // (the intents only ever run there), and this suite -- unlike
    // `IntentPlaybackTests` -- is not actor-isolated, so these two tests opt in
    // per-function rather than isolating the six entity-resolution tests above.
    @MainActor
    @Test("perform()'s playback call starts with reason .playAudioSchemaIntent and reports success once playing")
    func performsPlaybackCallReportsSuccessWhenPlaying() async {
        guard #available(iOS 27.0, *) else { return }

        let controller = FakeIntentPlaybackController()
        controller.isPlaying = true

        let started = await IntentPlayback.startAndAwait(
            reason: .playAudioSchemaIntent,
            controller: controller
        )

        #expect(started)
        #expect(controller.prepareForPlaybackCallCount == 1)
        #expect(controller.playedReasons == [.playAudioSchemaIntent])
    }

    @MainActor
    @Test("perform()'s playback call reports failure when playback never starts within the timeout")
    func performsPlaybackCallReportsFailureOnTimeout() async {
        guard #available(iOS 27.0, *) else { return }

        let controller = FakeIntentPlaybackController()

        let started = await IntentPlayback.startAndAwait(
            reason: .playAudioSchemaIntent,
            timeout: .milliseconds(300),
            controller: controller
        )

        #expect(!started, "A timed-out wait must report that playback never started")
        #expect(controller.playedReasons == [.playAudioSchemaIntent])
    }
}
#endif
