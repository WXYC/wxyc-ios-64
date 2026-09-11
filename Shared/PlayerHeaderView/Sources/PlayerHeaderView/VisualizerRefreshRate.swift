//
//  VisualizerRefreshRate.swift
//  PlayerHeaderView
//
//  Resolves the timeline interval the visualizer asks for, and reports the
//  current display's maximum refresh rate so the debug toggle can say whether
//  anything above 60 FPS is available on this device.
//
//  Created by Jake Bromberg on 09/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Refresh-rate policy for the visualizer's `TimelineView`.
///
/// The visualizer has always run at a fixed 60 FPS. On a ProMotion display it
/// can run at the panel's full rate, which this type opts into — but only when
/// the listener asks for it, since the extra frames cost power for an animation
/// most people glance at rather than watch.
public enum VisualizerRefreshRate {

    /// The rate the visualizer runs at unless high refresh rate is enabled.
    public static let baselineFramesPerSecond = 60

    /// The `minimumInterval` to hand `TimelineView(.animation(minimumInterval:paused:))`.
    ///
    /// When the opt-in is off this is always the 60 FPS interval, whatever the
    /// display can do. When it is on the visualizer asks for the display's
    /// maximum, never for anything slower than the 60 FPS baseline — a 30 Hz
    /// external display should not drag the visualizer below where it started.
    ///
    /// - Parameters:
    ///   - highRefreshRateEnabled: The listener's opt-in.
    ///   - displayMaximumFramesPerSecond: The display's maximum refresh rate.
    /// - Returns: The minimum interval between timeline updates, in seconds.
    public static func minimumInterval(
        highRefreshRateEnabled: Bool,
        displayMaximumFramesPerSecond: Int
    ) -> Double {
        guard highRefreshRateEnabled else {
            return 1.0 / Double(baselineFramesPerSecond)
        }
        let target = max(baselineFramesPerSecond, displayMaximumFramesPerSecond)
        return 1.0 / Double(target)
    }

    /// Whether a display's maximum rate is worth opting into.
    public static func supportsHighRefreshRate(displayMaximumFramesPerSecond: Int) -> Bool {
        displayMaximumFramesPerSecond > baselineFramesPerSecond
    }

    /// The maximum refresh rate of the display currently showing the app.
    ///
    /// Falls back to ``baselineFramesPerSecond`` when no display can be resolved,
    /// which keeps the opt-in inert rather than guessing high.
    ///
    /// - Note: On iPhone this reports the panel's capability, which is not the
    ///   same as permission to use it. iOS caps apps at 60 FPS on ProMotion
    ///   iPhones unless `CADisableMinimumFrameDurationOnPhone` is set in the
    ///   app's Info.plist.
    @MainActor
    public static var displayMaximumFramesPerSecond: Int {
#if os(iOS) || os(tvOS)
        let sceneMaximum = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map(\.screen.maximumFramesPerSecond)
            .max()
        return sceneMaximum ?? baselineFramesPerSecond
#elseif os(macOS)
        return NSScreen.main?.maximumFramesPerSecond ?? baselineFramesPerSecond
#else
        return baselineFramesPerSecond
#endif
    }
}
