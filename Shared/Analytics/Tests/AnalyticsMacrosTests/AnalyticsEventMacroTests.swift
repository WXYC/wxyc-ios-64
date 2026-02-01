//
//  AnalyticsEventMacroTests.swift
//  AnalyticsMacrosTests
//
//  Tests for the @AnalyticsEvent macro expansion.
//
//  Created by Claude on 01/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(AnalyticsMacros)
import AnalyticsMacros

let testMacros: [String: Macro.Type] = [
    "AnalyticsEvent": AnalyticsEventMacro.self,
]

final class AnalyticsEventMacroTests: XCTestCase {

    func testBasicExpansion() throws {
        assertMacroExpansion(
            """
            @AnalyticsEvent
            public struct AppLaunch {
                public let hasUsedThemePicker: Bool
                public let buildType: String
            }
            """,
            expandedSource: """
            public struct AppLaunch {
                public let hasUsedThemePicker: Bool
                public let buildType: String

                public static let name: String = "app_launch"

                public var properties: [String: Any]? {
                    [
                        "has_used_theme_picker": hasUsedThemePicker,
                        "build_type": buildType
                    ]
                }
            }

            extension AppLaunch: AnalyticsEvent {
            }
            """,
            macros: testMacros
        )
    }

    func testEmptyProperties() throws {
        assertMacroExpansion(
            """
            @AnalyticsEvent
            public struct PartyHornPresented {
            }
            """,
            expandedSource: """
            public struct PartyHornPresented {

                public static let name: String = "party_horn_presented"

                public var properties: [String: Any]? {
                    nil
                }
            }

            extension PartyHornPresented: AnalyticsEvent {
            }
            """,
            macros: testMacros
        )
    }

    func testExplicitNamePreserved() throws {
        assertMacroExpansion(
            """
            @AnalyticsEvent
            public struct AppLaunch {
                public static let name = "app launch"
                public let buildType: String
            }
            """,
            expandedSource: """
            public struct AppLaunch {
                public static let name = "app launch"
                public let buildType: String

                public var properties: [String: Any]? {
                    [
                        "build_type": buildType
                    ]
                }
            }

            extension AppLaunch: AnalyticsEvent {
            }
            """,
            macros: testMacros
        )
    }

    func testAcronymHandling() throws {
        assertMacroExpansion(
            """
            @AnalyticsEvent
            public struct CPUUsageEvent {
                public let averageCPU: Double
                public let maxCPU: Double
            }
            """,
            expandedSource: """
            public struct CPUUsageEvent {
                public let averageCPU: Double
                public let maxCPU: Double

                public static let name: String = "cpu_usage_event"

                public var properties: [String: Any]? {
                    [
                        "average_cpu": averageCPU,
                        "max_cpu": maxCPU
                    ]
                }
            }

            extension CPUUsageEvent: AnalyticsEvent {
            }
            """,
            macros: testMacros
        )
    }
}
#else
final class AnalyticsEventMacroTests: XCTestCase {
    func testMacrosNotAvailable() throws {
        XCTSkip("Macros not available on this platform")
    }
}
#endif
