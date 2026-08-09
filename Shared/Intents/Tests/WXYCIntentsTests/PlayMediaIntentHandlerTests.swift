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
    @Test("No explicit media item starts playback with .mediaSuggestion and returns success")
    func handleWithNoMediaItemsStartsPlaybackAndReturnsSuccess() async {
        var capturedReasons: [PlaybackReason] = []
        let handler = PlayMediaIntentHandler { reason in
            capturedReasons.append(reason)
            return true
        }

        let response = await handler.handle(intent: makeIntent())

        #expect(capturedReasons == [.mediaSuggestion])
        #expect(response.code == .success)
        #expect(response.userActivity == nil)
    }

    @Test("A start that never actually plays reports failure, not success")
    func handleReportsFailureWhenPlaybackNeverStarts() async {
        let handler = PlayMediaIntentHandler { _ in false }

        let response = await handler.handle(intent: makeIntent())

        #expect(response.code == .failure)
        #expect(response.userActivity == nil)
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
