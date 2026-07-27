//
//  BackgroundRefreshController.swift
//  WXYC
//
//  Namespace for the periodic background refresh task that fetches a fresh
//  playlist and reschedules the next refresh while the app is suspended.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import BackgroundTasks
import Foundation
import Logger

/// Namespace for the periodic background refresh task. Owns both the scheduling
/// of the next refresh and the work performed when iOS wakes the app to run one.
enum BackgroundRefreshController {
    static let taskIdentifier = "com.wxyc.refresh"

    /// Submits a new `BGAppRefreshTaskRequest` for ~15 minutes from now.
    ///
    /// - Parameters:
    ///   - scheduler: Where to submit the request. Defaults to the shared
    ///     system scheduler; tests inject a fake to exercise both the
    ///     unavailable-platform and genuine-failure paths.
    ///   - errorReporter: Where to send genuine scheduling failures. Defaults
    ///     to the global ``ErrorReporting/shared`` reporter.
    static func scheduleNext(
        scheduler: any BackgroundTaskScheduling = BGTaskScheduler.shared,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try scheduler.submit(request)
            Log(.info, category: .general, "Scheduled background refresh for 15 minutes from now")
        } catch let error as BGTaskScheduler.Error where error.code == .unavailable || error.code == .notPermitted {
            // Expected on the Simulator, on macOS ("Designed for iPad" on
            // Apple Silicon), and anywhere else BGTaskScheduler isn't
            // supported or permitted. Not a bug in our app, so log it for
            // local diagnosis but don't forward it to Sentry (Sentry IOS-20).
            let reason = error.code == .unavailable ? "unavailable" : "notPermitted"
            Log(.info, category: .general, "BGTaskScheduler \(reason) on this platform (code \(error.code.rawValue)); skipping background refresh scheduling")
        } catch {
            errorReporter.report(error, context: "BackgroundRefreshController.scheduleNext")
        }
    }

    /// Body of the `.backgroundTask(.appRefresh(taskIdentifier))` closure.
    ///
    /// Schedules the next refresh FIRST so the cycle continues even if iOS
    /// terminates the app during the fetch. Then fetches a fresh playlist
    /// (always hits the network, ignoring cache) with a 15-minute lifespan.
    /// Widget reload is handled separately by `WidgetStateService` observing
    /// playlist updates.
    static func handleRefresh(appState: Singletonia) async {
        scheduleNext()

        Log(.info, category: .general, "Background refresh started")

        let playlist = await appState.playlistService.fetchAndCachePlaylist()

        Log(.info, category: .general, "Background refresh completed successfully with \(playlist.entries.count) entries")

        // Fire the completion event BEFORE the Spotlight batch. `CSSearchableIndex.indexAppEntities`
        // for a cold-install 50-row window can take multi-second wall-clock, and BGAppRefresh's
        // ~30s budget is shared with the fetch above — if we donated first and hit the budget,
        // this analytics event would silently vanish precisely for the users we most want to
        // observe. Ordering the capture first guarantees the completion signal lands.
        StructuredPostHogAnalytics.shared.capture(BackgroundRefreshCompleted(
            entryCount: playlist.entries.count
        ))

        // Ingest into the playcut history directly rather than relying on the
        // playlist broadcast: the store's subscription races process suspension,
        // while this explicit call is guaranteed to land inside the budget. The
        // cheap local append runs before the potentially multi-second Spotlight
        // batch for the same reason the analytics capture does.
        await appState.playcutHistoryStore.ingest(playlist.playcuts)

        // Feeds both the `wxyc.playcuts` and `wxyc.artists` indexes from the
        // same fetched window on this refresh tick (see `donateBatch`).
        await appState.spotlightDonationService.donateBatch(from: playlist.playcuts)
    }
}
