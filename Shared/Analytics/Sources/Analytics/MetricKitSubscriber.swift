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
import Logger
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
            let period = DateInterval(start: payload.timeStampBegin, end: max(payload.timeStampBegin, payload.timeStampEnd))
            for diagnostic in payload.hangDiagnostics ?? [] {
                forward(.hang, json: diagnostic.jsonRepresentation(), period: period)
            }
            for diagnostic in payload.crashDiagnostics ?? [] {
                forward(.crash, json: diagnostic.jsonRepresentation(), period: period)
            }
        }
    }

    private func forward(_ kind: MetricKitDiagnosticMapper.Kind, json: Data, period: DateInterval) {
        let appBinaryName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        guard let event = MetricKitDiagnosticMapper.event(kind: kind, json: json, appBinaryName: appBinaryName, period: period) else {
            Log(.error, category: .general, "Dropped MetricKit \(kind.rawValue) diagnostic: its JSON (\(json.count) bytes) mapped to no event")
            return
        }
        analytics.capture(event)
    }
}
#endif
