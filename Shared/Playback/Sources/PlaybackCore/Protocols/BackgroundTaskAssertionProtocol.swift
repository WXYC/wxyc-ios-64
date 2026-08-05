//
//  BackgroundTaskAssertionProtocol.swift
//  Playback
//
//  Protocol for background-execution assertions (wraps UIApplication's
//  beginBackgroundTask/endBackgroundTask pair), so work that has to survive the
//  app being backgrounded can ask the system for the time to finish it without
//  this package reaching UIApplication directly.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Identifies one live background-execution assertion, so it can be ended again.
///
/// Mirrors `UIBackgroundTaskIdentifier` without exposing it, which is what keeps
/// the callers testable: the identifier's only meaning is "hand this back to
/// whoever issued it".
public struct BackgroundTaskID: Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Asks the system to keep the process running long enough to finish a piece of
/// work that a background transition would otherwise cut short.
///
/// Every assertion begun **must** be ended — the OS terminates apps that let one
/// run out — so callers should treat `beginTask` and `endTask` as a matched pair
/// on every exit path, including failures and expiration.
@MainActor
public protocol BackgroundTaskAssertionProtocol: AnyObject {
    /// Begins an assertion.
    ///
    /// - Parameters:
    ///   - name: Debug label, surfaced in the system logs when an assertion
    ///     expires.
    ///   - expirationHandler: Invoked shortly before the granted time runs out.
    ///     It **must** end the assertion; the process is killed otherwise.
    /// - Returns: The assertion's identifier, or `nil` if the system declined to
    ///   grant one (background execution disabled). A `nil` return is not an
    ///   error — the work simply proceeds unprotected, exactly as it did before.
    func beginTask(
        named name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskID?

    /// Ends an assertion. Ending one twice is a programming error, so callers
    /// track which of theirs are still live.
    func endTask(_ id: BackgroundTaskID)
}

#if os(iOS) || os(tvOS)

/// The real implementation, backed by `UIApplication`.
public final class SystemBackgroundTaskAssertion: BackgroundTaskAssertionProtocol {
    public init() {}

    public func beginTask(
        named name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskID? {
        let identifier = UIApplication.shared.beginBackgroundTask(
            withName: name,
            expirationHandler: expirationHandler
        )
        guard identifier != .invalid else { return nil }
        return BackgroundTaskID(rawValue: identifier.rawValue)
    }

    public func endTask(_ id: BackgroundTaskID) {
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: id.rawValue))
    }
}

#endif
