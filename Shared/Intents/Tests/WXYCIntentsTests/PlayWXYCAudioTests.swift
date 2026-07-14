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
}
#endif
