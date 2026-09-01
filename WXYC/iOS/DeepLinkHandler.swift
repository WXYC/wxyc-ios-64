//
//  DeepLinkHandler.swift
//  WXYC
//
//  Routes the deep links and hand-off / Siri user activities the app receives
//  through `onOpenURL` and `onContinueUserActivity` into the app's side effects.
//  Extracted from `AppLifecycleModifier` so the iOS lifecycle modifier and the
//  macOS one route identically — the two `@main` entry points can't drift on how
//  a `wxyc://` link or a shared show URL opens the app.
//
//  `action(for:)` is the pure, directly-testable routing decision; `perform(_:)`
//  turns a decision into the notification posts, playback starts, and analytics
//  it stands for. `WXYCDeepLink`'s URL parsing is covered by its own tests in the
//  Intents package; the tests here cover the case→action mapping and the
//  scheme-vs-universal-link source tagging that lives at this layer.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Core
import Foundation
import Intents
import Playback
import WXYCIntents

enum DeepLinkHandler {
    /// The routing decision for a received URL or user activity — the pure core
    /// that `perform(_:)` executes.
    enum Action: Equatable {
        /// Open the flowsheet on a specific playcut (`wxyc://playcut/<id>`).
        case openPlaycut(PlaycutID)
        /// Open the On Tour poster for a show. `source` records which link form
        /// matched so the tab can fold it into analytics once resolved.
        case openConcert(id: Int, source: ConcertOpenMessage.Source)
        /// Start the live stream for the given reason (a `wxyc://play` link, a
        /// hand-off continuation, …).
        case play(reason: PlaybackReason)
        /// Start the live stream from a legacy `INPlayMediaIntent` interaction,
        /// carrying the intent description for analytics.
        case playFromSiriIntent(description: String)
        /// Nothing recognised — the URL falls through to the system (Safari) or is
        /// ignored.
        case none
    }

    /// Resolves a URL delivered through `onOpenURL` — a `wxyc://` scheme link or
    /// the `https://wxyc.org/shows/<id>` universal link handed over as a Smart App
    /// Banner's `app-argument` — into a routing decision. URL-delivered concerts
    /// are tagged `.webBanner` when the URL carries `?src=web`, else `.scheme`; a
    /// *tapped* web link arrives as an `NSUserActivity` and is tagged
    /// `.universalLink` by `action(for:)` below.
    static func action(for url: URL) -> Action {
        switch WXYCDeepLink(routing: url) {
        case .playcut(let id): return .openPlaycut(id)
        case .concert(let id): return .openConcert(id: id, source: schemeSource(for: url))
        case .play: return .play(reason: .deepLink)
        case nil: return .none
        }
    }

    /// Separates a Smart App Banner tap from the app's own scheme links.
    ///
    /// Read here rather than in `WXYCDeepLink` because `src` is *provenance* and
    /// the parser's job is *destination* — source tagging already lives at this
    /// layer, which is where `.universalLink` is assigned too. (`WXYCDeepLink`
    /// never inspects query strings at all, so shipped builds tolerate links
    /// that gain parameters regardless of where the tag is read; that is a
    /// property of the parser, not a reason for this to live here.)
    ///
    /// An absent or unrecognised tag stays `.scheme` rather than inventing a
    /// fourth population out of a typo.
    private static func schemeSource(for url: URL) -> ConcertOpenMessage.Source {
        let src = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "src" }?
            .value
        return src == "web" ? .webBanner : .scheme
    }

    /// Resolves a hand-off / universal-link / Siri user activity into a routing
    /// decision. A tapped `https://wxyc.org/shows/<id>` web link is tagged
    /// `.universalLink`; a play-continuation reason starts the stream; a legacy
    /// `INPlayMediaIntent` interaction starts it from Siri. Any other web URL is
    /// ignored so it falls through to Safari.
    static func action(for userActivity: NSUserActivity) -> Action {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            if let webpageURL = userActivity.webpageURL,
               case .concert(let id)? = WXYCDeepLink(universalLink: webpageURL) {
                return .openConcert(id: id, source: .universalLink)
            }
            return .none
        } else if let reason = WXYCUserActivity.continuationReason(
            activityType: userActivity.activityType,
            userInfo: userActivity.userInfo
        ) {
            return .play(reason: reason)
        } else if let intent = userActivity.interaction?.intent as? INPlayMediaIntent {
            return .playFromSiriIntent(description: intent.description)
        }
        return .none
    }

    /// Executes a routing decision: posts the typed open message, starts playback,
    /// or captures the Siri-intent analytics.
    @MainActor
    static func perform(_ action: Action) {
        switch action {
        case .openPlaycut(let id):
            NotificationCenter.default.post(PlaycutOpenMessage(playcutID: id), subject: nil)
        case .openConcert(let id, let source):
            NotificationCenter.default.post(
                ConcertOpenMessage(concertID: id, source: source),
                subject: nil
            )
        case .play(let reason):
            AudioPlayerController.shared.play(reason: reason)
        case .playFromSiriIntent(let description):
            AudioPlayerController.shared.play(reason: .siriIntent)
            StructuredPostHogAnalytics.shared.capture(HandleINIntent(intentData: description))
        case .none:
            break
        }
    }

    /// Routes a URL end to end.
    @MainActor
    static func handle(url: URL) {
        perform(action(for: url))
    }

    /// Routes a user activity end to end.
    @MainActor
    static func handle(userActivity: NSUserActivity) {
        perform(action(for: userActivity))
    }
}
