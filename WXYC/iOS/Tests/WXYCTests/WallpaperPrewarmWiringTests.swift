//
//  WallpaperPrewarmWiringTests.swift
//  WXYC
//
//  Pins that the app's theme configuration is prewarmed where it is created
//  (#1144). The wallpaper's Metal pipelines have to be built before SwiftUI
//  lays the wallpaper out, or its first frame goes up without it and the UI is
//  drawn over the bare window. `ThemeConfiguration.prewarmSelectedTheme()`
//  starts that build, and nothing fails if the call goes missing: the
//  wallpaper still appears, about a second late.
//
//  Source-scanning for the reason `LaunchSequenceOrderingTests` gives. The
//  store the prewarm fills is internal to the Wallpaper package, so this
//  target has no runtime seam to read it through, and the only other signal is
//  a recorded launch.
//
//  Created by Jake Bromberg on 10/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing

@Suite("Wallpaper prewarm wiring")
struct WallpaperPrewarmWiringTests {

    @Test("Singletonia prewarms the theme configuration in the expression that creates it")
    func themeConfigurationIsPrewarmedWhereItIsCreated() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WXYCTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // iOS
            .appendingPathComponent("Singletonia.swift")

        let initializer = try SourceScan.boundedLines(
            of: url,
            start: { $0 == "let themeConfiguration: ThemeConfiguration = {" },
            startNotFoundMessage: """
            Singletonia.swift no longer creates `themeConfiguration` with a \
            closure initializer. Update this test's scan target rather than \
            deleting the check: wherever the configuration is created now, \
            `prewarmSelectedTheme()` has to be called on it straight away.
            """,
            open: "{",
            close: "}"
        )

        #expect(
            initializer.contains { $0.hasPrefix("configuration.prewarmSelectedTheme()") },
            """
            Singletonia creates the theme configuration without prewarming it. \
            The wallpaper's pipelines are then built only once its view is laid \
            out, which is too late for the app's first frame (#1144).
            """
        )
    }
}
