//
//  SentryLogsDestination.swift
//  WXYC
//
//  LogDestination that forwards log messages to Sentry Logs (the structured,
//  server-side-queryable logging product) at info and above. Debug-level
//  messages stay local; breadcrumbs (SentryBreadcrumbDestination) still
//  carry the full trail attached to error events.
//
//  Created by Jake Bromberg on 06/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import struct Logger.Category
import Sentry

/// Forwards log messages to Sentry Logs.
///
/// Registered via `Logger.addDestination(_:)` at app launch. Sentry batches
/// log emissions internally, so this is safe to call from the logging thread.
/// Filters out `.debug` to keep the Sentry Logs quota focused on meaningful
/// events; the breadcrumb destination still receives every level.
struct SentryLogsDestination: LogDestination {
    func receive(level: LogLevel, category: Category, message: String) {
        guard level >= .info else { return }
        let attributes: [String: Any] = ["category": category.rawValue]
        let logger = SentrySDK.logger
        switch level {
        case .debug: break
        case .info: logger.info(message, attributes: attributes)
        case .warning: logger.warn(message, attributes: attributes)
        case .error: logger.error(message, attributes: attributes)
        }
    }
}
