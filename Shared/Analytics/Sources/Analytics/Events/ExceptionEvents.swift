//
//  ExceptionEvents.swift
//  Analytics
//
//  PostHog `$exception` event for diagnostics collected outside the SDK's own
//  autocapture, such as MetricKit hangs and crashes.
//
//  Created by Jake Bromberg on 10/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A PostHog error-tracking `$exception` event.
///
/// Distinct from ``ErrorEvent``: this is the event PostHog's error tracking groups
/// into issues, so `exceptionList` follows its `$exception_list` shape.
public struct ExceptionEvent: AnalyticsEvent {
    public static let name = "$exception"

    /// Where the diagnostic came from, e.g. `"metrickit"`.
    public let source: String
    /// What kind of diagnostic it is, e.g. `"hang"` or `"crash"`.
    public let diagnosticKind: String
    public let exceptionList: [[String: any Sendable]]

    public var properties: [String: Any]? {
        [
            "$exception_list": exceptionList,
            "$exception_level": "fatal",
            "source": source,
            "diagnostic_kind": diagnosticKind,
        ]
    }

    public init(source: String, diagnosticKind: String, exceptionList: [[String: any Sendable]]) {
        self.source = source
        self.diagnosticKind = diagnosticKind
        self.exceptionList = exceptionList
    }
}
