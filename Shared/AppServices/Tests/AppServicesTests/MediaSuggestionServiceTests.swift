//
//  MediaSuggestionServiceTests.swift
//  AppServices
//
//  Verifies MediaSuggestionService.register() (#828): it publishes an
//  INMediaUserContext declaring WXYC as a media app with one playable item,
//  seeds INUpcomingMediaManager with exactly the canonical WXYC play intent
//  (nil artwork — the #740 main-actor compositing hazard this service must
//  not reintroduce) in .onlyPredictSuggestedIntents mode for .radioStation,
//  and captures a MediaSuggestionRegistered baseline event so the follow-on
//  device observation can tell "iOS declined" from "register() never ran."
//  All three are exercised against recording spies, mirroring
//  HandoffActivityManager's protocol-plus-spy pattern
//  (WXYC/iOS/Tests/WXYCTests/HandoffActivityManagerTests.swift) — never
//  against the real INMediaUserContext/INUpcomingMediaManager singletons.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import Analytics
import AnalyticsTesting
import Intents
import Testing
@testable import AppServices

@Suite("MediaSuggestionService")
@MainActor
struct MediaSuggestionServiceTests {
    @Test("register() publishes a subscribed, one-item INMediaUserContext")
    func registerPublishesMediaUserContext() {
        let contextSpy = SpyMediaUserContextPublisher()
        let service = MediaSuggestionService(
            contextPublisher: contextSpy,
            upcomingMedia: SpyUpcomingMediaSuggesting(),
            analytics: MockStructuredAnalytics()
        )

        service.register()

        #expect(contextSpy.publishedContexts.count == 1)
        #expect(contextSpy.publishedContexts.first?.subscriptionStatus == .subscribed)
        #expect(contextSpy.publishedContexts.first?.numberOfLibraryItems == 1)
    }

    @Test("register() seeds exactly one suggested intent with nil artwork")
    func registerSeedsOneSuggestedIntentWithNilArtwork() {
        let upcomingSpy = SpyUpcomingMediaSuggesting()
        let service = MediaSuggestionService(
            contextPublisher: SpyMediaUserContextPublisher(),
            upcomingMedia: upcomingSpy,
            analytics: MockStructuredAnalytics()
        )

        service.register()

        #expect(upcomingSpy.suggestedIntentSets.count == 1)
        let intents = upcomingSpy.suggestedIntentSets.first?.array as? [INPlayMediaIntent]
        #expect(intents?.count == 1)
        #expect(intents?.first?.mediaItems?.first?.artwork == nil)
    }

    @Test("register() sets .onlyPredictSuggestedIntents for .radioStation")
    func registerSetsPredictionMode() {
        let upcomingSpy = SpyUpcomingMediaSuggesting()
        let service = MediaSuggestionService(
            contextPublisher: SpyMediaUserContextPublisher(),
            upcomingMedia: upcomingSpy,
            analytics: MockStructuredAnalytics()
        )

        service.register()

        #expect(upcomingSpy.predictionModeCalls.count == 1)
        #expect(upcomingSpy.predictionModeCalls.first?.mode == .onlyPredictSuggestedIntents)
        #expect(upcomingSpy.predictionModeCalls.first?.type == .radioStation)
    }

    @Test("register() captures a MediaSuggestionRegistered baseline event")
    func registerCapturesRegistrationEvent() {
        let analytics = MockStructuredAnalytics()
        let service = MediaSuggestionService(
            contextPublisher: SpyMediaUserContextPublisher(),
            upcomingMedia: SpyUpcomingMediaSuggesting(),
            analytics: analytics
        )

        service.register()

        #expect(analytics.typedEvents(ofType: MediaSuggestionRegistered.self).count == 1)
    }
}

// MARK: - Spies

/// Records every `INMediaUserContext` handed to `becomeCurrent(_:)`, so a
/// test can inspect the context's `.subscriptionStatus` /
/// `.numberOfLibraryItems` without touching the real, app-global
/// `INUserContext.becomeCurrent()` machinery.
@MainActor
private final class SpyMediaUserContextPublisher: MediaUserContextPublishing {
    private(set) var publishedContexts: [INMediaUserContext] = []

    func becomeCurrent(_ context: INMediaUserContext) {
        publishedContexts.append(context)
    }
}

/// Records every call `MediaSuggestionService.register()` makes against
/// `INUpcomingMediaManager`'s two methods, so a test can assert on exactly
/// what was seeded without touching the real, app-global
/// `INUpcomingMediaManager.shared` singleton.
@MainActor
private final class SpyUpcomingMediaSuggesting: UpcomingMediaSuggesting {
    private(set) var suggestedIntentSets: [NSOrderedSet] = []
    private(set) var predictionModeCalls: [(mode: INUpcomingMediaPredictionMode, type: INMediaItemType)] = []

    func setSuggestedMediaIntents(_ intents: NSOrderedSet) {
        suggestedIntentSets.append(intents)
    }

    func setPredictionMode(_ mode: INUpcomingMediaPredictionMode, for type: INMediaItemType) {
        predictionModeCalls.append((mode: mode, type: type))
    }
}
#endif
