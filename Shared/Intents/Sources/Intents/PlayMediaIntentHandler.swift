//
//  PlayMediaIntentHandler.swift
//  Intents
//
//  Handles a directly-dispatched INPlayMediaIntent — the media-suggestion tile
//  iOS offers after headphones connect (INUpcomingMediaManager, #828), or a
//  replayed Siri media request. Returned from AppDelegate.application(_:handlerFor:)
//  so iOS can launch the app in the background and start playback without a
//  foreground UI, unlike the existing NSUserActivity continuation
//  (AppLifecycleModifier.swift:144), which requires one. See
//  docs/plans/media-suggestion-headphones.md (PR 2) and issue #829.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS)
import Foundation
import Intents
import PlaybackCore

/// Handles `INPlayMediaIntent` dispatched directly to the app (no Intents
/// extension), so a media-suggestion tile can start playback in the
/// background. Returned from `AppDelegate.application(_:handlerFor:)`.
///
/// Deliberately *not* `@MainActor`: `INPlayMediaIntent`/`INPlayMediaIntentResponse`
/// aren't `Sendable`, so a main-actor-isolated `handle(intent:)` can't satisfy
/// `INPlayMediaIntentHandling` without sending them across that boundary. The
/// `start` closure still reaches `AudioPlayerController.shared` by hopping onto
/// `@MainActor` itself, inside `IntentPlayback.startAndAwait`.
public final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    private let start: (PlaybackReason) async -> Void

    /// Internal seam initializer. `PlayMediaIntentHandler` must be `public`
    /// (the app-target `AppDelegate` returns it), but `IntentPlayback` is
    /// internal to this module — Swift forbids a `public` initializer's
    /// default argument from referencing an internal declaration. This
    /// initializer carries the injectable `start` closure so tests can
    /// substitute a spy without touching the real `AudioPlayerController`;
    /// `init()` below forwards to it with the real implementation as an
    /// ordinary delegating call, not a default argument.
    init(start: @escaping (PlaybackReason) async -> Void) {
        self.start = start
    }

    public override convenience init() {
        self.init(start: { await IntentPlayback.startAndAwait(reason: $0) })
    }

    public func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        await start(.mediaSuggestion)
        return INPlayMediaIntentResponse(code: .success, userActivity: nil)
    }
}
#endif
