//
//  WidgetSafeSpotlightReindexer.swift
//  Intents
//
//  The `SpotlightReindexer` default `AppIntentsDependencies.registerForWidget()`
//  registers, for every entity kind. The NowPlayingWidget extension process
//  never initiates a Spotlight reindex itself, so a donation ask reaching this
//  conformer in that process is discarded rather than trapping on an
//  unregistered `@Dependency` (#751).
//
//  One generic type, not one per kind: #751 landed `WidgetSafePlaycutReindexer`
//  and `WidgetSafeConcertReindexer` against the two per-kind protocols that
//  existed when it was written, and #758 replaced those protocols with the
//  single generic `SpotlightReindexer<Source>` — leaving two shims whose bodies
//  were character-identical modulo the element type. Neither slice could see
//  that; it is only visible with both landed. A third entity kind now costs an
//  instantiation, not a file.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Discards every donation silently, for any `Source`. Silence is the whole
/// contract here — unlike `WidgetSafeAnalyticsService`, which logs, because
/// there the fact that the widget process was asked at all is the signal
/// someone wants; and unlike `WidgetSafeConcertsFetching`, which throws,
/// because a fabricated empty page would read to Spotlight as a positive
/// "the index should now be empty." A dropped reindex ask needs neither: the
/// app process re-donates the same entities on its own schedule, so nothing
/// is lost and nothing false is asserted.
struct WidgetSafeSpotlightReindexer<Source>: SpotlightReindexer {
    func donate(_ items: [Source]) async throws {}
}
