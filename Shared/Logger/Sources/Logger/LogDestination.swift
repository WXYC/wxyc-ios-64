//
//  LogDestination.swift
//  Logger
//
//  Protocol for receiving log messages, enabling external integrations
//  (e.g., Sentry breadcrumbs) without adding SDK dependencies to Logger.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A destination that receives log messages after they have been written
/// to the standard outputs (os.Logger, print, file).
///
/// Register destinations via ``Logger/addDestination(_:)`` at app launch.
///
/// ## Thread Safety
///
/// Implementations of ``receive(level:category:message:)`` **must** be
/// non-blocking and thread-safe. Blocking calls (locks, synchronous I/O)
/// will degrade logging throughput. The method is called synchronously on
/// the caller's thread, outside of any Logger-internal locks.
public protocol LogDestination: Sendable {
    /// Called for each log message that passes the level filter.
    ///
    /// - Parameters:
    ///   - level: The severity level of the log message.
    ///   - category: The category the message was logged under.
    ///   - message: The fully formatted log string (timestamp, file, category, etc.).
    func receive(level: LogLevel, category: Category, message: String)
}
