//
//  PendingConcertLink.swift
//  WXYC
//
//  The app's "a shared show link is waiting to be opened" state (#537). A tapped
//  `https://wxyc.org/shows/<id>` (or `wxyc://concert/<id>`) link posts a typed
//  `ConcertOpenMessage`; `Singletonia` catches it and stashes this value, which
//  `RootTabView` reacts to (flipping to the On Tour tab) and `OnTourTabView`
//  consumes (running the resolution ladder, then clearing it).
//
//  `source` is already the analytics label ("universalLink" / "scheme") — the
//  `ConcertOpenMessage.Source.rawValue`, mapped at the `Singletonia` boundary so
//  the On Tour views never import `Intents`. `Equatable` so it can key an
//  `.onChange` / `.task(id:)`.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A pending request to open an On Tour show, carried from the deep-link handler
/// to the On Tour tab.
struct PendingConcertLink: Equatable, Sendable {
    /// The concert id from the shared link.
    let id: Int

    /// The link form that opened the app, already in analytics-label form
    /// ("universalLink" or "scheme") for the `ConcertDeepLinkOpened` event.
    let source: String
}
