//
//  TourAlertScheduling.swift
//  AppServices
//
//  The seam between the tour-alert decision (`TourAlertCoordinator`) and the
//  platform notification API. The concrete production implementation lives in
//  the app target under `#if DEBUG` (it wraps `UNUserNotificationCenter` and
//  owns authorization + foreground presentation); tests substitute a recording
//  double. References only ``TourAlert``, so it stays ungated.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Posts a resolved ``TourAlert`` to the platform. Implementations own their own
/// authorization handling and no-op silently when notifications are unavailable.
public protocol TourAlertScheduling: Sendable {
    func post(_ alert: TourAlert) async
}
