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
    /// Must be called on the main actor (BGTaskScheduler requirement).
    @MainActor
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            Log(.info, category: .general, "Scheduled background refresh for 15 minutes from now")
        } catch {
            ErrorReporting.shared.report(error, context: "scheduleBackgroundRefresh")
        }
    }

    /// Body of the `.backgroundTask(.appRefresh(taskIdentifier))` closure: schedules
    /// the next refresh first (so the cycle continues if iOS terminates us mid-fetch),
    /// then fetches and caches a fresh playlist and reports completion to analytics.
    static func handleRefresh(appState: Singletonia) async {
        await MainActor.run { scheduleNext() }

        Log(.info, category: .general, "Background refresh started")

        let playlist = await appState.playlistService.fetchAndCachePlaylist()

        Log(.info, category: .general, "Background refresh completed successfully with \(playlist.entries.count) entries")

        StructuredPostHogAnalytics.shared.capture(BackgroundRefreshCompleted(
            entryCount: playlist.entries.count
        ))
    }
}
