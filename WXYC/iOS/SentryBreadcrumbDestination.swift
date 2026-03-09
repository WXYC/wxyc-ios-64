//
//  SentryBreadcrumbDestination.swift
//  WXYC
//
//  LogDestination that converts log messages into Sentry breadcrumbs,
//  providing a trail of context leading up to error reports.
//
//  Created by Jake Bromberg on 03/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import struct Logger.Category
import Sentry

/// Forwards log messages to Sentry as breadcrumbs.
///
/// Registered via `Logger.addDestination(_:)` at app launch. Sentry's
/// `addBreadcrumb` is thread-safe and non-blocking, so this is safe to
/// call from the logging thread.
struct SentryBreadcrumbDestination: LogDestination {
    func receive(level: LogLevel, category: Category, message: String) {
        let crumb = Breadcrumb(level: sentryLevel(for: level), category: category.rawValue)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    private func sentryLevel(for level: LogLevel) -> SentryLevel {
        switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}
