//
//  AnalyticsEventNameTests.swift
//  Analytics
//
//  Tests for automatic event name derivation from type names.
//
//  Created by Claude on 01/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("Analytics Event Name Derivation")
struct AnalyticsEventNameTests {

    // MARK: - Snake Case Conversion

    @Test("Simple PascalCase converts to snake_case")
    func simplePascalCase() {
        #expect("QualitySessionSummary".convertedToSnakeCase() == "quality_session_summary")
        #expect("ThemePickerState".convertedToSnakeCase() == "theme_picker_state")
        #expect("PlaybackStarted".convertedToSnakeCase() == "playback_started")
    }

    @Test("Acronyms stay together")
    func acronymsStayTogether() {
        #expect("CPUUsage".convertedToSnakeCase() == "cpu_usage")
        #expect("CPUUsageEvent".convertedToSnakeCase() == "cpu_usage_event")
        #expect("URLSession".convertedToSnakeCase() == "url_session")
        #expect("HTTPSConnection".convertedToSnakeCase() == "https_connection")
    }

    @Test("Trailing acronyms handled correctly")
    func trailingAcronyms() {
        #expect("ConnectionHTTPS".convertedToSnakeCase() == "connection_https")
        #expect("UsageCPU".convertedToSnakeCase() == "usage_cpu")
    }

    @Test("Single word converts to lowercase")
    func singleWord() {
        #expect("Error".convertedToSnakeCase() == "error")
        #expect("Interruption".convertedToSnakeCase() == "interruption")
    }

    @Test("Empty string returns empty")
    func emptyString() {
        #expect("".convertedToSnakeCase() == "")
    }

    // MARK: - Event Name Derivation

    @Test("Event types derive correct names")
    func eventTypeNames() {
        // These are the expected new event names (accessed via static property)
        #expect(TestEvent.name == "test_event")
        #expect(QualityTestEvent.name == "quality_test_event")
        #expect(CPUTestEvent.name == "cpu_test_event")
    }
}

// MARK: - Test Event Types

private struct TestEvent: AnalyticsEvent {
    var properties: [String: Any]? { nil }
}

private struct QualityTestEvent: AnalyticsEvent {
    var properties: [String: Any]? { nil }
}

private struct CPUTestEvent: AnalyticsEvent {
    var properties: [String: Any]? { nil }
}
