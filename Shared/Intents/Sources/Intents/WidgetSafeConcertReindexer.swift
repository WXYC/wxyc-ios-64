//
//  WidgetSafeConcertReindexer.swift
//  Intents
//
//  The `ConcertReindexer` default `AppIntentsDependencies.registerForWidget()`
//  registers, mirroring `WidgetSafePlaycutReindexer`. The NowPlayingWidget
//  extension process never initiates a Spotlight reindex itself, so a
//  donation ask reaching this conformer in that process is discarded rather
//  than trapping on an unregistered `@Dependency` (#751).
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Foundation

/// Discards every donation silently.
struct WidgetSafeConcertReindexer: ConcertReindexer {
    func donate(_ concerts: [Concert]) async throws {}
}
