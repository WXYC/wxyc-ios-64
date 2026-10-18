//
//  PostHogLogsDestination.swift
//  WXYC
//
//  LogDestination that forwards warning and error log messages to PostHog
//  Logs. Info and debug stay local (info-level lifecycle chatter is ~97% of
//  volume); breadcrumbs still carry the full trail attached to error events.
//
//  Created by Jake Bromberg on 10/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import PostHog

/// Abstraction over the subset of `PostHogSDK.shared.logger` that
/// `PostHogLogsDestination` uses. Allows injecting a fake in tests without
/// touching the real PostHog SDK.
///
/// The methods are `nonisolated` because `LogDestination.receive(...)` is
/// invoked from arbitrary threads (`Logger` does no actor hopping).
protocol PostHogLogEmitter: Sendable {
    nonisolated func warn(_ message: String, attributes: [String: Any])
    nonisolated func error(_ message: String, attributes: [String: Any])
}

/// Adapter exposing `PostHogSDK.shared.logger` through the `PostHogLogEmitter`
/// protocol. The logger is created by `PostHogSDK.setup` and is `nil` before
/// it (or after `close()`), so it is resolved on every emission; lines logged
/// outside that window are dropped.
struct PostHogSDKLoggerEmitter: PostHogLogEmitter {
    nonisolated func warn(_ message: String, attributes: [String: Any]) {
        PostHogSDK.shared.logger?.warn(message, attributes: attributes)
    }

    nonisolated func error(_ message: String, attributes: [String: Any]) {
        PostHogSDK.shared.logger?.error(message, attributes: attributes)
    }
}

/// Forwards warning and error log messages to PostHog Logs.
///
/// Registered via `Logger.addDestination(_:)` at app launch. The incoming
/// `message` is the fully formatted log string from `Logger`; the prefix is
/// stripped (shared with `SentryLogsDestination`) so the body carries only the
/// developer-authored message, and the category is lifted into an attribute.
struct PostHogLogsDestination: LogDestination {
    private let emitter: any PostHogLogEmitter

    init(emitter: any PostHogLogEmitter = PostHogSDKLoggerEmitter()) {
        self.emitter = emitter
    }

    func receive(level: LogLevel, category: LogCategory, message: String) {
        let body = SentryLogsDestination.stripFormattedPrefix(from: message)
        let attributes: [String: Any] = ["category": category.rawValue]

        switch level {
        case .warning: emitter.warn(body, attributes: attributes)
        case .error: emitter.error(body, attributes: attributes)
        default: break // info and debug stay local
        }
    }
}
