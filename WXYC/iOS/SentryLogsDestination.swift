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

/// Abstraction over the subset of `SentrySDK.logger` that `SentryLogsDestination`
/// uses. Allows injecting a fake in tests without touching the real Sentry SDK.
///
/// The methods are `nonisolated` because `LogDestination.receive(...)` is
/// invoked from arbitrary threads (`Logger` does no actor hopping).
///
/// The `[String: Any]` attribute type mirrors the public sentry-cocoa 8.x
/// `SentryLogger` API; sentry-cocoa converts each value into a typed
/// `SentryLog.Attribute` internally (String/Bool/Int/Double, others stringified).
protocol SentryLogEmitter: Sendable {
    nonisolated func info(_ message: String, attributes: [String: Any])
    nonisolated func warn(_ message: String, attributes: [String: Any])
    nonisolated func error(_ message: String, attributes: [String: Any])
}

/// Adapter exposing `SentrySDK.logger` through the `SentryLogEmitter` protocol.
/// Resolves the per-call accessor on every emission, matching the pattern used
/// by `SentryBreadcrumbDestination` so SDK initialization order is unconstrained.
struct SentrySDKLoggerEmitter: SentryLogEmitter {
    nonisolated func info(_ message: String, attributes: [String: Any]) {
        SentrySDK.logger.info(message, attributes: attributes)
    }

    nonisolated func warn(_ message: String, attributes: [String: Any]) {
        SentrySDK.logger.warn(message, attributes: attributes)
    }

    nonisolated func error(_ message: String, attributes: [String: Any]) {
        SentrySDK.logger.error(message, attributes: attributes)
    }
}

/// Forwards log messages to Sentry Logs.
///
/// Registered via `Logger.addDestination(_:)` at app launch. Sentry batches log
/// emissions internally (`SentryLogBatcher`), so this is safe to call from the
/// logging thread. Filters out `.debug` to keep the Sentry Logs quota focused
/// on meaningful events; the breadcrumb destination still receives every level.
///
/// The incoming `message` is the fully formatted log string from `Logger`
/// (timestamp, file, line, function, `[category/level]` prefix, body). We strip
/// the prefix before forwarding so Sentry's body field carries only the
/// developer-authored message, and we lift the category into an attribute so
/// it can be filtered server-side. Recovering `file`/`line`/`function` as
/// structured attributes would require a `LogDestination` API change to pass
/// those values separately; for now they remain inside the prefix that Sentry
/// drops on the floor.
struct SentryLogsDestination: LogDestination {
    private let emitter: any SentryLogEmitter

    init(emitter: any SentryLogEmitter = SentrySDKLoggerEmitter()) {
        self.emitter = emitter
    }

    func receive(level: LogLevel, category: Category, message: String) {
        guard level >= .info else { return }

        let body = Self.stripFormattedPrefix(from: message)
        let attributes: [String: Any] = ["category": category.rawValue]

        switch level {
        case .info: emitter.info(body, attributes: attributes)
        case .warning: emitter.warn(body, attributes: attributes)
        case .error: emitter.error(body, attributes: attributes)
        default: break // .debug filtered above; future levels degrade silently
        }
    }

    /// Removes Logger's formatted prefix, returning only the developer-authored body.
    ///
    /// `Logger` emits messages in the shape
    /// `"<timestamp> <file>:<line> <function> [<category>/<level>] <body>"`.
    /// We anchor on the `[<category>/<level>] ` token because it's the only
    /// bracketed token in the format and is followed by `"] "`. If the marker
    /// is missing (e.g. the format changes), the original message is returned
    /// unmodified so the body still reaches Sentry.
    static func stripFormattedPrefix(from message: String) -> String {
        guard let markerEnd = message.range(of: "] ") else { return message }
        return String(message[markerEnd.upperBound...])
    }
}
