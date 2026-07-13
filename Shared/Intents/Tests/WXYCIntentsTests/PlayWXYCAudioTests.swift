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
    @Test("The station entity resolves to the single WXYC live station")
    func liveRadioStationResolves() async throws {
        guard #available(iOS 27.0, *) else { return }

        let station = try await LiveRadioStationEntity.defaultQuery.uniqueEntity()

        #expect(station.id == "org.wxyc.live")
        #expect(station.title == "WXYC 89.3 FM")
        #expect(station.providerName == "WXYC Chapel Hill")
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
