//
//  MediaSuggestionService.swift
//  AppServices
//
//  Declares WXYC eligible for iOS's media-suggestion engine (#828): the
//  headphone-connect / CarPlay-connect "play" tile on the Home Screen Siri
//  Suggestions row and the Lock Screen. WXYC already donated
//  `INPlayMediaIntent` at launch and on play, but donations alone accumulate
//  as generic shortcut history, not media-app signal — `INMediaUserContext`
//  is the declaration that registers the app as a media app with playable
//  content, and `INUpcomingMediaManager` is the API that hands iOS the
//  concrete intent to offer. Neither existed before this file; see
//  docs/plans/media-suggestion-headphones.md for the full design.
//
//  Gated `#if os(iOS) && !targetEnvironment(macCatalyst)`, not a bare
//  `#if os(iOS)`: `INUpcomingMediaManager` is
//  `API_AVAILABLE(ios, watchos) API_UNAVAILABLE(macos, tvos)`, and the WXYC
//  target sets `SUPPORTS_MACCATALYST = YES` — Catalyst inherits iOS
//  availability, so a bare `os(iOS)` check would compile *and run* this on
//  the Mac, where the suggestion surface does not exist.
//
//  `@MainActor`, not an actor: `INMediaUserContext.becomeCurrent()` and
//  `INUpcomingMediaManager.sharedManager` are app-global system state, the
//  same category of work `HandoffActivityManager` already models as
//  main-actor-isolated. It holds no state of its own — registers once at
//  launch and is never retained (see "Ownership" in the design doc) — so a
//  struct is enough; there's nothing an actor's serialization would protect.
//
//  Test seams mirror HandoffActivityManager's protocol-plus-spy pattern.
//  Both protocols are `public`: MediaSuggestionService is constructed from
//  WXYCApp.init() in the app target, so its initializer must be `public`,
//  and a `public` initializer's default argument can't reference an
//  internal declaration.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import Analytics
import Foundation
import Intents
import PlaybackCore

/// Abstracts `INMediaUserContext.becomeCurrent()` — a `becomeCurrent(_:)`
/// that takes the context as a parameter, rather than a protocol the context
/// itself conforms to, so a test spy can capture and inspect the exact
/// `INMediaUserContext` `MediaSuggestionService` built (its
/// `.subscriptionStatus` / `.numberOfLibraryItems`) instead of only
/// observing that *some* call happened.
@MainActor
public protocol MediaUserContextPublishing {
    func becomeCurrent(_ context: INMediaUserContext)
}

/// The real conformer: forwards straight to `INUserContext.becomeCurrent()`.
public struct SystemMediaUserContextPublisher: MediaUserContextPublishing {
    public init() {}

    public func becomeCurrent(_ context: INMediaUserContext) {
        context.becomeCurrent()
    }
}

/// Abstracts the pair of `INUpcomingMediaManager` methods
/// `MediaSuggestionService` needs, for testability. The method signatures
/// match `INUpcomingMediaManager`'s own instance methods exactly, so the
/// real conformer is a plain extension rather than a wrapper type — see
/// below.
@MainActor
public protocol UpcomingMediaSuggesting {
    func setSuggestedMediaIntents(_ intents: NSOrderedSet)
    func setPredictionMode(_ mode: INUpcomingMediaPredictionMode, for type: INMediaItemType)
}

extension INUpcomingMediaManager: UpcomingMediaSuggesting {}

/// Registers WXYC with iOS's media-suggestion engine: publishes an
/// `INMediaUserContext` declaring it a media app with one playable item (the
/// live station), and seeds `INUpcomingMediaManager` with the canonical WXYC
/// play intent so there is something for the system to offer when the user
/// connects headphones or starts driving.
@MainActor
public struct MediaSuggestionService {
    private let contextPublisher: MediaUserContextPublishing
    private let upcomingMedia: UpcomingMediaSuggesting
    private let analytics: AnalyticsService

    public init(
        contextPublisher: MediaUserContextPublishing = SystemMediaUserContextPublisher(),
        upcomingMedia: UpcomingMediaSuggesting = INUpcomingMediaManager.shared,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared
    ) {
        self.contextPublisher = contextPublisher
        self.upcomingMedia = upcomingMedia
        self.analytics = analytics
    }

    /// Publishes the media user context, seeds the suggested intent, and
    /// captures the `MediaSuggestionRegistered` baseline event. Idempotent
    /// to call repeatedly — `INMediaUserContext` is not persistent, so
    /// `WXYCApp.init()` re-publishes it on every launch.
    public func register() {
        let context = INMediaUserContext()
        // "This user can play content," not "this user pays" — correct for
        // a free stream.
        context.subscriptionStatus = .subscribed
        // One playable thing: the live station. See the design doc's "Open
        // questions" for why LikedSongs isn't folded into this count.
        context.numberOfLibraryItems = 1
        contextPublisher.becomeCurrent(context)

        // nil artwork: this runs on the main actor at launch, and
        // compositing UIImage.placeholder here would reintroduce the #740
        // hang. The suggestion tile falls back to the app icon.
        let intent = MediaIntentBuilder.makePlayMediaIntent(artwork: nil)
        upcomingMedia.setSuggestedMediaIntents(NSOrderedSet(array: [intent]))
        // WXYC has exactly one playable thing; without this, iOS would try
        // to predict individual playcuts from donation history and could
        // offer a tile that can't be honored.
        upcomingMedia.setPredictionMode(.onlyPredictSuggestedIntents, for: .radioStation)

        analytics.capture(MediaSuggestionRegistered())
    }
}
#endif
