//
//  CompositeErrorReporterTests.swift
//  WXYC
//
//  Pins that CompositeErrorReporter forwards each report's static context to
//  the exception gate as its dedupe label (#1201), so two call sites raising
//  the same error stay separate keys while the runtime `context` property
//  keeps the same text.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation
import Logger
import Testing
@testable import WXYC

@Suite("CompositeErrorReporter")
struct CompositeErrorReporterTests {
    @Test("Forwards the static context as a non-empty dedupe label")
    func forwardsContextAsLabel() {
        let analytics = RecordingAnalytics()
        let reporter = CompositeErrorReporter(analytics: analytics)

        reporter.report(NSError(domain: "TestDomain", code: 1), context: "DiskCache allMetadata", category: .caching)

        #expect(analytics.dedupeLabels == ["DiskCache allMetadata"])
    }

    @Test("Gives two call sites that raise the same error different labels")
    func differentCallSitesGetDifferentLabels() {
        let analytics = RecordingAnalytics()
        let reporter = CompositeErrorReporter(analytics: analytics)
        let error = NSError(domain: "TestDomain", code: 1)

        reporter.report(error, context: "DiskCache data(for:): failed to read file", category: .caching)
        reporter.report(error, context: "DiskCache allMetadata", category: .caching)
        reporter.report(error, context: "DiskCache allMetadata", category: .caching)

        #expect(analytics.dedupeLabels == [
            "DiskCache data(for:): failed to read file",
            "DiskCache allMetadata",
            "DiskCache allMetadata",
        ])
    }

    @Test("Keeps the context text as a property on the exception")
    func contextRemainsAProperty() {
        let analytics = RecordingAnalytics()
        let reporter = CompositeErrorReporter(analytics: analytics)

        reporter.report(NSError(domain: "TestDomain", code: 1), context: "feedbackEmail", category: .ui)

        #expect(analytics.exceptionProperties.first?["context"] as? String == "feedbackEmail")
    }
}

/// Records exception labels and properties without depending on the
/// `AnalyticsTesting` package (not linked into this target).
private final class RecordingAnalytics: AnalyticsService, @unchecked Sendable {
    private let lock = NSLock()
    private var _dedupeLabels: [String] = []
    private var _exceptionProperties: [[String: Any]] = []

    var dedupeLabels: [String] { lock.withLock { _dedupeLabels } }
    var exceptionProperties: [[String: Any]] { lock.withLock { _exceptionProperties } }

    func capture<T: AnalyticsEvent>(_ event: T) {}

    func captureException(_ error: any Error, properties: [String: Any]?, dedupeLabel: StaticString) {
        lock.withLock {
            _dedupeLabels.append(String(describing: dedupeLabel))
            _exceptionProperties.append(properties ?? [:])
        }
    }
}
