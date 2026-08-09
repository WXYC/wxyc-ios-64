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
import Core
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

        let response = await handler.handle(intent: makeIntent(mediaItems: nil))

        #expect(capturedReasons == [.mediaSuggestion])
        #expect(response.code == .success)
        #expect(response.userActivity == nil)
    }

    @Test("A media item carrying WXYC's own identifier starts playback and returns success")
    func handleWithOurIdentifierStartsPlaybackAndReturnsSuccess() async {
        var capturedReasons: [PlaybackReason] = []
        let handler = PlayMediaIntentHandler { reason in
            capturedReasons.append(reason)
            return true
        }

        let response = await handler.handle(intent: makeIntent(mediaItems: [makeMediaItem(identifier: RadioStation.WXYC.identifier)]))

        #expect(capturedReasons == [.mediaSuggestion])
        #expect(response.code == .success)
        #expect(response.userActivity == nil)
    }

    @Test("A media item carrying a foreign identifier is rejected without starting playback")
    func handleWithForeignIdentifierRejectsWithoutStartingPlayback() async {
        var capturedReasons: [PlaybackReason] = []
        let handler = PlayMediaIntentHandler { reason in
            capturedReasons.append(reason)
            return true
        }

        let response = await handler.handle(intent: makeIntent(mediaItems: [makeMediaItem(identifier: "com.apple.music.some-other-song")]))

        #expect(capturedReasons.isEmpty, "A foreign media item must not start WXYC playback")
        #expect(response.code == .failureUnknownMediaType)
        #expect(response.userActivity == nil)
    }

    @Test("A start that never actually plays reports failure, not success")
    func handleReportsFailureWhenPlaybackNeverStarts() async {
        let handler = PlayMediaIntentHandler { _ in false }

        let response = await handler.handle(intent: makeIntent(mediaItems: nil))

        #expect(response.code == .failure)
        #expect(response.userActivity == nil)
    }

    @Test("public init() constructs and rejects a foreign media item without touching the real start path")
    func defaultInitializerRejectsForeignMediaWithoutStartingPlayback() async {
        // Constructing with the public initializer must not require access to
        // anything beyond WXYCIntents' public surface — this is the whole
        // point of the internal-init/public-init split (#829): PlayMediaIntentHandler
        // is public (the app-target delegate returns it), but IntentPlayback is
        // internal, so the real start closure can't be a public default argument.
        //
        // This exercises that real, un-substituted start closure end to end,
        // without touching AudioPlayerController.shared or requiring RUN_E2E:
        // the foreign-identifier guard in handle(intent:) rejects and returns
        // before the closure is ever invoked, so there's nothing to await or
        // time out on.
        let handler = PlayMediaIntentHandler()

        let response = await handler.handle(intent: makeIntent(mediaItems: [makeMediaItem(identifier: "com.apple.music.some-other-song")]))

        #expect(response.code == .failureUnknownMediaType)
        #expect(response.userActivity == nil)
    }
}

private func makeIntent(mediaItems: [INMediaItem]?) -> INPlayMediaIntent {
    INPlayMediaIntent(
        mediaItems: mediaItems,
        mediaContainer: nil,
        playShuffled: nil,
        resumePlayback: nil,
        playbackQueueLocation: .unknown,
        playbackSpeed: nil
    )
}

private func makeMediaItem(identifier: String) -> INMediaItem {
    INMediaItem(identifier: identifier, title: "Some Other Media", type: .song, artwork: nil)
}
#endif
