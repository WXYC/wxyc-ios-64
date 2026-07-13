//
//  IntentTitleTests.swift
//  WXYCIntents
//
//  Guards against duplicate user-facing intent titles. Two AudioPlaybackIntents
//  sharing an identical title ("Play WXYC") is ambiguous to the system's intent
//  disambiguation and Siri Semantic Understanding layers.
//
//  Created by Jake Bromberg on 07/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Testing
@testable import WXYCIntents

@Suite("Intent titles")
struct IntentTitleTests {
    /// The playback-control intents must each carry a distinct title. A shared
    /// title makes the two `AudioStarting` actions indistinguishable in the
    /// App Intents metadata that Siri and Shortcuts consume.
    @Test("PlayWXYC and ToggleWXYC have distinct titles")
    func playAndToggleTitlesAreDistinct() {
        #expect(PlayWXYC.title != ToggleWXYC.title)
    }

    @Test("Each playback intent has the expected title")
    func expectedTitles() {
        #expect(PlayWXYC.title == "Play WXYC")
        #expect(PauseWXYC.title == "Pause WXYC")
        #expect(ToggleWXYC.title == "Toggle WXYC")
    }

    #if compiler(>=6.4)
    /// With the iOS 27 audio-schema intent added, all three playback intents must
    /// still carry pairwise-distinct titles: a shared title makes the `AudioStarting`
    /// actions indistinguishable in the metadata Siri's media-domain routing consumes.
    @Test("All three playback intents have pairwise-distinct titles")
    func allPlaybackTitlesArePairwiseDistinct() {
        guard #available(iOS 27.0, *) else { return }

        let titles: [LocalizedStringResource] = [PlayWXYC.title, ToggleWXYC.title, PlayWXYCAudio.title]

        for i in titles.indices {
            for j in titles.indices where j > i {
                #expect(titles[i] != titles[j], "Playback intent titles must be pairwise distinct")
            }
        }
    }
    #endif
}
