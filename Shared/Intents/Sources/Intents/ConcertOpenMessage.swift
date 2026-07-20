//
//  ConcertOpenMessage.swift
//  Intents
//
//  Typed "open this On Tour show" message that flows through NotificationCenter
//  via the Shared/Core MainActorNotificationMessage machinery. Posted by the
//  universal-link / scheme handler in AppLifecycleModifier when a shared
//  `https://wxyc.org/shows/<id>` (or `wxyc://concert/<id>`) link opens the app,
//  and observed by RootTabView, which flips to the On Tour tab and hands the id
//  to the tab's resolution ladder (#537).
//
//  Subject is `NSObject` because the message has no natural emitter to filter
//  by (both link forms are "the app opening a URL"). Callers pass `nil`.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

public struct ConcertOpenMessage: MainActorNotificationMessage {
    public typealias Subject = NSObject

    /// Which link form opened the app. Known only at parse time (which
    /// initializer matched), so it rides along in the message for the On Tour
    /// tab to fold into the `ConcertDeepLinkOpened` analytics event once the
    /// resolution ladder finishes.
    public enum Source: String, Sendable {
        /// `https://wxyc.org/shows/<id>` — a shared public link (a friend tapped it).
        case universalLink
        /// `wxyc://concert/<id>` — an app-owned surface (Spotlight, shortcut).
        case scheme
    }

    public static let name = Notification.Name("org.wxyc.iphoneapp.openConcert")

    public let concertID: Int
    public let source: Source

    public init(concertID: Int, source: Source) {
        self.concertID = concertID
        self.source = source
    }

    public static func makeMessage(_ notification: sending Notification) -> Self? {
        guard notification.name == name,
              let id = notification.userInfo?["concertID"] as? Int,
              let rawSource = notification.userInfo?["source"] as? String,
              let source = Source(rawValue: rawSource)
        else {
            return nil
        }
        return Self(concertID: id, source: source)
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: NSObject?) -> Notification {
        Notification(
            name: name,
            object: object,
            userInfo: [
                "concertID": message.concertID,
                "source": message.source.rawValue,
            ]
        )
    }
}
