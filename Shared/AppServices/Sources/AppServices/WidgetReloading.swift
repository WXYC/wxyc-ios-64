//
//  WidgetReloading.swift
//  AppServices
//
//  Protocol abstracting WidgetCenter's timeline reload API for testability.
//  The production implementation delegates to the shared center; tests inject
//  a mock to verify which reloads the app actually issues.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(WidgetKit)
import WidgetKit

/// Abstracts `WidgetCenter` so reload behavior can be asserted without the
/// system API — which silently no-ops under test, making the difference
/// between "reloaded" and "declined to reload" invisible.
@MainActor
public protocol WidgetReloading: Sendable {
    func reloadAllTimelines()
}

/// Production implementation that delegates to `WidgetCenter.shared`.
@MainActor
public struct SystemWidgetReloader: WidgetReloading {
    public init() {}

    public func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
