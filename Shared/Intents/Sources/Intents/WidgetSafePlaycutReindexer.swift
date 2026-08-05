//
//  WidgetSafePlaycutReindexer.swift
//  Intents
//
//  The `PlaycutReindexer` default `AppIntentsDependencies.registerForWidget()`
//  registers. The NowPlayingWidget extension process never initiates a
//  Spotlight reindex itself, so a donation ask reaching this conformer in
//  that process is discarded rather than trapping on an unregistered
//  `@Dependency` (#751).
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Discards every donation silently.
struct WidgetSafePlaycutReindexer: PlaycutReindexer {
    func donate(_ entities: [PlaycutEntity]) async throws {}
}
