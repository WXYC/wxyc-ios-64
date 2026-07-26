//
//  BackgroundTaskScheduling.swift
//  WXYC
//
//  Injectable seam over BGTaskScheduler's submission API. BGTaskScheduler.shared
//  is a hard system singleton, so BackgroundRefreshController.scheduleNext()
//  accepts anything conforming to this protocol, letting tests substitute a
//  fake that can be told to throw specific errors (e.g. the platform-
//  unavailable case that's expected on the Simulator and on macOS).
//
//  Created by Jake Bromberg on 07/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import BackgroundTasks
import Foundation

/// Minimal seam over `BGTaskScheduler.submit(_:)` so callers can be tested
/// without touching the real system scheduler.
protocol BackgroundTaskScheduling {
    /// Submits a background task request for execution.
    ///
    /// - Parameter request: The task request to schedule.
    /// - Throws: `BGTaskScheduler.Error` (or another error) if the request
    ///   couldn't be submitted.
    func submit(_ request: BGTaskRequest) throws
}

extension BGTaskScheduler: BackgroundTaskScheduling {}
