//
//  MetricKitSubscriber.swift
//  Analytics
//
//  Forwards MetricKit hang and crash diagnostics to PostHog as `$exception`
//  events. iOS only: watchOS has no PostHog exception autocapture to match.
//
//  Created by Jake Bromberg on 10/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS)
import Foundation
import MetricKit

/// Subscribes to `MXMetricManager` and captures each hang and crash diagnostic through the
/// injected ``AnalyticsService``. Sentry's own MetricKit integration stays off.
public final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    public static let shared = MetricKitSubscriber()

    private let analytics: any AnalyticsService

    public init(analytics: any AnalyticsService = StructuredPostHogAnalytics.shared) {
        self.analytics = analytics
    }

    /// Registers with MetricKit, which then delivers payloads on later launches too.
    public func start() {
        MXMetricManager.shared.add(self)
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for diagnostic in payload.hangDiagnostics ?? [] {
                forward(.hang, json: diagnostic.jsonRepresentation())
            }
            for diagnostic in payload.crashDiagnostics ?? [] {
                forward(.crash, json: diagnostic.jsonRepresentation())
            }
        }
    }

    private func forward(_ kind: MetricKitDiagnosticMapper.Kind, json: Data) {
        guard let event = MetricKitDiagnosticMapper.event(kind: kind, json: json) else { return }
        analytics.capture(event)
    }
}
#endif
