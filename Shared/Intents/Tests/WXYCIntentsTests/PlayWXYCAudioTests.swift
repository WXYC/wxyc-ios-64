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
import PlaybackCore
import Testing
@testable import WXYCIntents

@Suite("PlayWXYCAudio (iOS 27 audio schema)")
struct PlayWXYCAudioTests {
    /// Spoken phrasings whose relevant search term Siri hands the audio query
    /// for "play WXYC". Each must resolve to the one station — this is the path
    /// `.audio.playAudio` actually uses, and the one a `UniqueAppEntityQuery`
    /// left unanswered ("I can't find the station WXYC").
    static let stationSearchTerms = ["WXYC", "wxyc", "WXYC 89.3", "WXYC 89.3 FM", "89.3 FM"]

    @Test("Audio search for the station name resolves to WXYC", arguments: stationSearchTerms)
    func audioSearchResolvesStation(term: String) async throws {
        guard #available(iOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(matching: term)

        #expect(matches.count == 1)
        #expect(matches.first?.id == "org.wxyc.live")
        #expect(matches.first?.title == "WXYC 89.3 FM")
    }

    @Test("Audio search for an unrelated term resolves nothing")
    func audioSearchIgnoresUnrelatedTerms() async throws {
        guard #available(iOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(matching: "the weather tomorrow")

        #expect(matches.isEmpty)
    }

    @Test("The station resolves back from its stable identifier")
    func stationResolvesByIdentifier() async throws {
        guard #available(iOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(for: ["org.wxyc.live"])

        #expect(matches.count == 1)
        #expect(matches.first?.title == "WXYC 89.3 FM")
    }

    @Test("An unknown identifier resolves to nothing")
    func unknownIdentifierResolvesNothing() async throws {
        guard #available(iOS 27.0, *) else { return }

        let matches = try await LiveRadioStationEntity.defaultQuery.entities(for: ["org.example.other"])

        #expect(matches.isEmpty)
    }

    @Test("The station entity's initializer carries stable identity")
    func liveRadioStationInitializer() {
        guard #available(iOS 27.0, *) else { return }

        let station = LiveRadioStationEntity()

        #expect(station.id == "org.wxyc.live")
        #expect(station.title == "WXYC 89.3 FM")
    }

    @Test("The intent starts playback in the background without opening the app")
    func intentRunsInBackground() {
        guard #available(iOS 27.0, *) else { return }

        #expect(PlayWXYCAudio.openAppWhenRun == false)
    }

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
