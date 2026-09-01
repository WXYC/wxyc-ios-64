//
//  ConcertOpenMessage.swift
//  Intents
//
//  Typed "open this On Tour show" message that flows through NotificationCenter
//  via the shared `OpenMessage`/`MainActorNotificationMessage` machinery.
//  Posted by the universal-link / scheme handler in AppLifecycleModifier when a
//  shared `https://wxyc.org/shows/<id>` (or `wxyc://concert/<id>`) link opens
//  the app, and observed by RootTabView, which flips to the On Tour tab and
//  hands the id to the tab's resolution ladder (#537).
//
//  Subject is `NSObject` because the message has no natural emitter to filter
//  by (both link forms are "the app opening a URL"). Callers pass `nil`.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

public struct ConcertOpenMessage: OpenMessage {
    public typealias Subject = NSObject

    /// Which link form opened the app. Known only at parse time (which
    /// initializer matched), so it rides along in the message for the On Tour
    /// tab to fold into the `ConcertDeepLinkOpened` analytics event once the
    /// resolution ladder finishes.
    /// `CaseIterable` so the round-trip test enumerates `allCases` rather than a
    /// hand-listed array — the encode/`Source(rawValue:)` hop is where an
    /// unknown raw value makes `makePayload` return `nil` and drops the link
    /// silently, and a hand-listed array leaves each new case uncovered while
    /// still passing.
    public enum Source: String, Sendable, CaseIterable {
        /// `https://wxyc.org/shows/<id>` — a shared public link (a friend tapped it).
        case universalLink
        /// `wxyc://concert/<id>` — an app-owned surface (Spotlight, shortcut).
        case scheme
        /// `wxyc://concert/<id>?src=web` — the Smart App Banner on the show's own
        /// web page. Split out of ``scheme`` because it is the only one of those
        /// arrivals that represents reach from *outside* the app, and lumping it
        /// in made "how much traffic does the website send us" unanswerable.
        case webBanner
    }

    public static let name = Notification.Name("org.wxyc.iphoneapp.openConcert")

    public struct Payload: NotificationPayload {
        public let concertID: Int
        public let source: Source

        public static func makePayload(userInfo: [AnyHashable: Any]?) -> Self? {
            guard let concertID = userInfo?["concertID"] as? Int,
                  let rawSource = userInfo?["source"] as? String,
                  let source = Source(rawValue: rawSource)
            else {
                return nil
            }
            return Self(concertID: concertID, source: source)
        }

        public var userInfoEntries: [AnyHashable: Any] {
            [
                "concertID": concertID,
                "source": source.rawValue,
            ]
        }
    }

    public let payload: Payload

    public init(payload: Payload) {
        self.payload = payload
    }

    public init(concertID: Int, source: Source) {
        self.payload = Payload(concertID: concertID, source: source)
    }

    public var concertID: Int { payload.concertID }
    public var source: Source { payload.source }
}
