//
//  PlayMediaIntentHandlerTests.swift
//  WXYCIntents
//
//  Covers the background-capable INPlayMediaIntent handler (#829): the
//  media-suggestion tile's direct-dispatch target, reached from
//  AppDelegate.application(_:handlerFor:) without a foreground launch. Tests
//  exercise the injectable start seam rather than the real AudioPlayerController,
//  so this suite runs in the normal test batch — no RUN_E2E requirement, unlike
//  PlayWXYCIntentTests.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS)
import Intents
import Testing
import PlaybackCore
@testable import WXYCIntents

// Deliberately not @MainActor: PlayMediaIntentHandler.handle(intent:) is
// nonisolated (see its doc comment — INPlayMediaIntent/INPlayMediaIntentResponse
// aren't Sendable), and calling a nonisolated async method on a non-Sendable
// class from a main-actor-isolated caller trips Swift 6's "sending risks data
// races" check even though nothing here actually races.
@Suite("PlayMediaIntentHandler")
struct PlayMediaIntentHandlerTests {
    @Test("handle(intent:) starts playback with .mediaSuggestion and returns success")
    func handleStartsPlaybackAndReturnsSuccess() async {
        var capturedReasons: [PlaybackReason] = []
        let handler = PlayMediaIntentHandler { reason in
            capturedReasons.append(reason)
        }

        let response = await handler.handle(intent: makeIntent())

        #expect(capturedReasons == [.mediaSuggestion])
        #expect(response.code == .success)
        #expect(response.userActivity == nil)
    }

    @Test("public init() forwards to the real IntentPlayback start path")
    func defaultInitializerUsesRealStartPath() {
        // Constructing with the public initializer must not require access to
        // anything beyond WXYCIntents' public surface — this is the whole
        // point of the internal-init/public-init split (#829): PlayMediaIntentHandler
        // is public (the app-target delegate returns it), but IntentPlayback is
        // internal, so the real start closure can't be a public default argument.
        _ = PlayMediaIntentHandler()
    }
}

private func makeIntent() -> INPlayMediaIntent {
    INPlayMediaIntent(
        mediaItems: nil,
        mediaContainer: nil,
        playShuffled: nil,
        resumePlayback: nil,
        playbackQueueLocation: .unknown,
        playbackSpeed: nil
    )
}
#endif
