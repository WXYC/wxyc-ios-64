//
//  UserDefaults+WXYC.swift
//  Caching
//
//  Shared UserDefaults for App Group access from widgets and extensions.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - UserDefaults Extension

public extension UserDefaults {
    /// Shared UserDefaults instance for the WXYC App Group.
    ///
    /// This UserDefaults instance is backed by the App Group container
    /// `group.wxyc.iphone`, making stored values accessible from:
    /// - The main WXYC app
    /// - The NowPlaying widget
    /// - The Share extension
    /// - Any other targets in the App Group
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Store a value
    /// UserDefaults.wxyc.set("1.2.3", forKey: "lastKnownVersion")
    ///
    /// // Read a value
    /// let version = UserDefaults.wxyc.string(forKey: "lastKnownVersion")
    /// ```
    ///
    /// ## Thread Safety
    ///
    /// Marked `nonisolated(unsafe)` because `UserDefaults` is thread-safe
    /// and this is a static constant initialized once.
    ///
    /// - Important: The force unwrap is safe because the App Group is configured
    ///   in the app's entitlements. If the suite name is invalid, the app would
    ///   fail at build/signing time, not runtime.
    nonisolated(unsafe) static let wxyc = UserDefaults(suiteName: "group.wxyc.iphone")!
}
