//
//  WindowColorSchemeTests.swift
//  WXYC
//
//  Guards the regression that flattened the default wallpaper to a single
//  palette. WXYC 1983 is a `swiftUI`-renderer theme whose entire visual is
//  `WXYCGradient`, which picks its light or dark stops from
//  `environment.colorScheme` — so that branch *is* the theme's light/dark
//  support. `preferredColorScheme` is a window-level preference: applied
//  anywhere in the tree it overrides the whole window, including the wallpaper,
//  which is a sibling of the content it was attached to. Pinning it for the
//  status bar's sake therefore left the dark stops resolving in every
//  appearance, and silently killed `crossfadeColorSchemeTransitions()` too,
//  which only fires on a window trait change.
//
//  The status bar never needed the pin: Info.plist's UIStatusBarStyle +
//  UIViewControllerBasedStatusBarAppearance pair keeps it light content on its
//  own, verified in both appearances in the simulator.
//
//  Created by Jake Bromberg on 08/27/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import UIKit
@testable import WXYC

@Suite("Window color scheme")
@MainActor
struct WindowColorSchemeTests {
    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    /// The exact shape of the regression: a window (or its root controller)
    /// carrying an explicit style means something upstream pinned
    /// `preferredColorScheme`, and the wallpaper has lost an appearance.
    @Test("No window pins a user interface style")
    func noWindowPinsUserInterfaceStyle() async throws {
        try await waitForWindows()

        for window in windows {
            #expect(
                window.overrideUserInterfaceStyle == .unspecified,
                "\(type(of: window)) pins \(window.overrideUserInterfaceStyle.rawValue)"
            )
            #expect(window.rootViewController?.overrideUserInterfaceStyle == .unspecified)
        }
    }

    /// The status bar's actual mechanism, asserted so a future reader doesn't
    /// reintroduce the pin believing these keys are inert in a scene-based app.
    @Test("Info.plist owns the light status bar style")
    func infoPlistOwnsLightStatusBarStyle() throws {
        // WXYCTests is host-app-tested (TEST_HOST = WXYC.app), so Bundle.main
        // resolves to the running WXYC app's bundle, not the test bundle.
        let style = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UIStatusBarStyle") as? String
        )
        let isViewControllerBased = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UIViewControllerBasedStatusBarAppearance") as? Bool
        )

        #expect(style == "UIStatusBarStyleLightContent")
        #expect(!isViewControllerBased)
    }

    private func waitForWindows(timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while windows.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(!windows.isEmpty, "host app never produced a window")
    }
}
