//
//  DeepLinkHandlerTests.swift
//  WXYC
//
//  Verifies DeepLinkHandler's routing decisions: the case→action mapping for
//  every `wxyc://…` link and the scheme-vs-universal-link source tagging that
//  distinguishes a URL opened through `onOpenURL` (`.scheme`) from a web link
//  tapped and handed over as an `NSUserActivity` (`.universalLink`). The URL
//  parsing itself is covered by `WXYCDeepLinkTests` in the Intents package.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PlaybackCore
import Testing
import WXYCIntents
@testable import WXYC

@Suite("DeepLinkHandler routing")
struct DeepLinkHandlerTests {
    @Test("wxyc://play routes to a deep-link stream start")
    func schemePlay() {
        #expect(DeepLinkHandler.action(for: URL(string: "wxyc://play")!) == .play(reason: .deepLink))
    }

    @Test("wxyc://concert/<id> routes to an open-concert tagged .scheme")
    func schemeConcert() {
        #expect(
            DeepLinkHandler.action(for: URL(string: "wxyc://concert/4821")!)
                == .openConcert(id: 4821, source: .scheme)
        )
    }

    @Test("A URL-delivered universal link is still tagged .scheme")
    func universalLinkThroughURLIsScheme() {
        // A Smart App Banner hands its share URL to `onOpenURL`, so it routes
        // through `action(for: URL)` and is tagged `.scheme`, not `.universalLink`.
        #expect(
            DeepLinkHandler.action(for: URL(string: "https://wxyc.org/shows/4821")!)
                == .openConcert(id: 4821, source: .scheme)
        )
    }

    @Test("?src=web separates a Smart App Banner tap from the app's own scheme links")
    func webBannerSourceTag() {
        // Without this, `.scheme` conflates three unrelated populations —
        // Spotlight, Shortcuts, and everyone arriving from the website — and the
        // web banner is the only one of the three that represents reach outside
        // the app. `WXYCDeepLink` ignores query strings, so the tag is read here.
        #expect(
            DeepLinkHandler.action(for: URL(string: "wxyc://concert/4821?src=web")!)
                == .openConcert(id: 4821, source: .webBanner)
        )
    }

    @Test("An unrecognised or absent src leaves the link tagged .scheme")
    func unknownSourceTagFallsBackToScheme() {
        // Shipped builds must keep resolving links that gain parameters later,
        // and a typo'd tag must not invent a fourth population.
        for url in [
            "wxyc://concert/4821",
            "wxyc://concert/4821?src=",
            "wxyc://concert/4821?src=widget",
            "wxyc://concert/4821?utm_source=web",
        ] {
            #expect(
                DeepLinkHandler.action(for: URL(string: url)!)
                    == .openConcert(id: 4821, source: .scheme)
            )
        }
    }

    @Test("wxyc://playcut/<id> routes to an open-playcut")
    func schemePlaycut() {
        guard case .openPlaycut = DeepLinkHandler.action(for: URL(string: "wxyc://playcut/9")!) else {
            Issue.record("expected .openPlaycut")
            return
        }
    }

    @Test("An unrecognised URL routes to none")
    func unrecognisedURL() {
        #expect(DeepLinkHandler.action(for: URL(string: "https://example.com/foo")!) == .none)
    }

    @Test("A tapped show web link routes to an open-concert tagged .universalLink")
    func browsingWebConcertIsUniversalLink() {
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = URL(string: "https://wxyc.org/shows/4821")
        #expect(DeepLinkHandler.action(for: activity) == .openConcert(id: 4821, source: .universalLink))
    }

    @Test("A tapped non-show web link is ignored")
    func browsingWebNonConcertIsNone() {
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = URL(string: "https://wxyc.org/blog/hello")
        #expect(DeepLinkHandler.action(for: activity) == .none)
    }

    @Test("A Handoff play-continuation routes to .play(reason: .handoff)")
    func continuationHandoff() {
        let activity = NSUserActivity(activityType: WXYCUserActivity.play)
        activity.userInfo = ["origin": "handoff"]
        #expect(DeepLinkHandler.action(for: activity) == .play(reason: .handoff))
    }

    @Test("A quick-action / Siri-prediction play-continuation routes to .play(reason: .quickAction)")
    func continuationQuickAction() {
        // Same activity type, no `origin: handoff` marker — the home-screen quick
        // action and the donated Siri/Spotlight prediction keep `.quickAction`.
        let activity = NSUserActivity(activityType: WXYCUserActivity.play)
        #expect(DeepLinkHandler.action(for: activity) == .play(reason: .quickAction))
    }
}
