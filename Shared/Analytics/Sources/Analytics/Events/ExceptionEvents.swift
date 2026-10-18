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
    /// The binary images the frames reference, sent as `$debug_images` so PostHog can
    /// match each frame's `image_addr` to a dSYM. Omitted when empty.
    public let debugImages: [[String: any Sendable]]
    /// Per-occurrence details, such as a hang's duration. Kept out of the exception's
    /// `value` so they do not split one failure into many issues.
    public let additionalProperties: [String: any Sendable]

    public var properties: [String: Any]? {
        var result: [String: Any] = [
            "$exception_list": exceptionList,
            "$exception_level": "fatal",
            "source": source,
            "diagnostic_kind": diagnosticKind,
        ]
        if !debugImages.isEmpty {
            result["$debug_images"] = debugImages
        }
        result.merge(additionalProperties) { current, _ in current }
        return result
    }

    public init(
        source: String,
        diagnosticKind: String,
        exceptionList: [[String: any Sendable]],
        debugImages: [[String: any Sendable]] = [],
        additionalProperties: [String: any Sendable] = [:]
    ) {
        self.source = source
        self.diagnosticKind = diagnosticKind
        self.exceptionList = exceptionList
        self.debugImages = debugImages
        self.additionalProperties = additionalProperties
    }
}
