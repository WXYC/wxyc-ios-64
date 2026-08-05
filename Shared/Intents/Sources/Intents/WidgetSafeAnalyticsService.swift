//
//  WidgetSafeAnalyticsService.swift
//  Intents
//
//  The `AnalyticsService` default `AppIntentsDependencies.registerForWidget()`
//  registers. The NowPlayingWidget extension process has no PostHog session
//  of its own to report into, so every captured event is discarded silently
//  rather than trapping on an unregistered `@Dependency` (#751).
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation

/// Discards every captured event silently.
struct WidgetSafeAnalyticsService: AnalyticsService {
    func capture<T: AnalyticsEvent>(_ event: T) {}
}
