//
//  WallpaperMacroTests.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import XCTest
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import WallpaperMacroPlugin

final class WallpaperMacroTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Wallpaper": WallpaperMacro.self]

    func testMacroExpansion() {
        assertMacroExpansion(
            """
            @Wallpaper
            public final class TestWallpaper: WallpaperProtocol {
                public let displayName = "Test"
                public func configure() { }
                public func makeView() -> EmptyView { EmptyView() }
                public func makeDebugControls() -> EmptyView? { nil }
                public func reset() { }
            }
            """,
            expandedSource: """
            public final class TestWallpaper: WallpaperProtocol {
                public let displayName = "Test"
                public func configure() { }
                public func makeView() -> EmptyView { EmptyView() }
                public func makeDebugControls() -> EmptyView? { nil }
                public func reset() { }

                private static let _registered: Bool = {
                    WallpaperProvider.shared.registerType(TestWallpaper.self)
                    return true
                }()

                public init() {
                    _ = Self._registered
                    self.configure()
                }
            }
            """,
            macros: macros
        )
    }

    func testNotAClassDiagnostic() {
        assertMacroExpansion(
            """
            @Wallpaper
            struct NotAClass { }
            """,
            expandedSource: """
            struct NotAClass { }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Wallpaper can only be applied to a class", line: 1, column: 1)
            ],
            macros: macros
        )
    }

    func testClassWithExistingInitDiagnostic() {
        assertMacroExpansion(
            """
            @Wallpaper
            public final class BadWallpaper: WallpaperProtocol {
                public let displayName = "Bad"
                public init() { }
                public func configure() { }
                public func makeView() -> EmptyView { EmptyView() }
                public func makeDebugControls() -> EmptyView? { nil }
                public func reset() { }
            }
            """,
            expandedSource: """
            public final class BadWallpaper: WallpaperProtocol {
                public let displayName = "Bad"
                public init() { }
                public func configure() { }
                public func makeView() -> EmptyView { EmptyView() }
                public func makeDebugControls() -> EmptyView? { nil }
                public func reset() { }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Wallpaper generates init() - remove your init() and use configure() instead", line: 1, column: 1)
            ],
            macros: macros
        )
    }

    func testInitWithParametersIsAllowed() {
        // An init with parameters should not conflict with the generated parameterless init
        assertMacroExpansion(
            """
            @Wallpaper
            public final class ParameterizedWallpaper: WallpaperProtocol {
                public let displayName = "Parameterized"
                public init(name: String) { }
                public func configure() { }
                public func makeView() -> EmptyView { EmptyView() }
                public func makeDebugControls() -> EmptyView? { nil }
                public func reset() { }
            }
            """,
            expandedSource: """
            public final class ParameterizedWallpaper: WallpaperProtocol {
                public let displayName = "Parameterized"
                public init(name: String) { }
                public func configure() { }
                public func makeView() -> EmptyView { EmptyView() }
                public func makeDebugControls() -> EmptyView? { nil }
                public func reset() { }

                private static let _registered: Bool = {
                    WallpaperProvider.shared.registerType(ParameterizedWallpaper.self)
                    return true
                }()

                public init() {
                    _ = Self._registered
                    self.configure()
                }
            }
            """,
            macros: macros
        )
    }
}
