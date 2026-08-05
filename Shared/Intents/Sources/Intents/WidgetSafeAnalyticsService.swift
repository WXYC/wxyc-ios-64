//
//  WidgetSafeAnalyticsService.swift
//  Intents
//
//  The `AnalyticsService` default `AppIntentsDependencies.registerForWidget()`
//  registers. The NowPlayingWidget extension process has no PostHog session
//  of its own to report into, so every captured event is dropped rather than
//  forwarded -- but it is logged, not silently discarded (#751 review,
//  non-blocking finding): a fully silent no-op would erase the one signal
//  that would tell anyone whether the OS ever actually routes a
//  PlaycutEntityQuery/ConcertEntityQuery reindex ask to this process at all,
//  which is exactly the evidence AC4's deferred manual check (see
//  `NowPlayingWidgetBundle.init()`) needs. The appex already links Analytics
//  for this protocol; Logger costs nothing extra.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation
import Logger

/// Logs every captured event's name instead of forwarding it anywhere.
struct WidgetSafeAnalyticsService: AnalyticsService {
    func capture<T: AnalyticsEvent>(_ event: T) {
        Log(.info, category: .general, "Widget process captured \(T.name) (discarded -- no PostHog session in this process)")
    }
}
