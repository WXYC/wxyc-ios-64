//
//  SentryLogsDestinationTests.swift
//  WXYC
//
//  Tests for SentryLogsDestination: level filtering, prefix stripping,
//  category-attribute forwarding, and per-level routing.
//
//  Created by Jake Bromberg on 06/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Logger
import struct Logger.Category
@testable import WXYC

@Suite("SentryLogsDestination")
struct SentryLogsDestinationTests {

    @Test(".debug is dropped before reaching the emitter")
    func debugIsDropped() {
        let emitter = RecordingEmitter()
        let destination = SentryLogsDestination(emitter: emitter)

        destination.receive(
            level: .debug,
            category: .general,
            message: formatted(.debug, category: .general, body: "noisy")
        )

        #expect(emitter.calls.isEmpty)
    }

    @Test(
        ".info / .warning / .error route to the matching emitter method",
        arguments: [
            (LogLevel.info, EmitterMethod.info),
            (LogLevel.warning, EmitterMethod.warn),
            (LogLevel.error, EmitterMethod.error)
        ]
    )
    func levelsRouteToMatchingMethod(level: LogLevel, expectedMethod: EmitterMethod) {
        let emitter = RecordingEmitter()
        let destination = SentryLogsDestination(emitter: emitter)

        destination.receive(
            level: level,
            category: .playback,
            message: formatted(level, category: .playback, body: "real body")
        )

        #expect(emitter.calls.count == 1)
        #expect(emitter.calls.first?.method == expectedMethod)
    }

    @Test("category is forwarded as an attribute")
    func categoryForwardedAsAttribute() {
        let emitter = RecordingEmitter()
        let destination = SentryLogsDestination(emitter: emitter)

        destination.receive(
            level: .warning,
            category: .network,
            message: formatted(.warning, category: .network, body: "DNS slow")
        )

        let call = try? #require(emitter.calls.first)
        #expect(call?.attributes["category"] as? String == Category.network.rawValue)
    }

    @Test("formatted prefix is stripped, leaving only the developer body")
    func prefixIsStripped() {
        let emitter = RecordingEmitter()
        let destination = SentryLogsDestination(emitter: emitter)

        let body = "Stream stalled after 12s"
        destination.receive(
            level: .error,
            category: .playback,
            message: formatted(.error, category: .playback, body: body)
        )

        #expect(emitter.calls.first?.message == body)
    }

    @Test("messages without the bracketed marker are forwarded unmodified")
    func bareMessagePassesThrough() {
        let emitter = RecordingEmitter()
        let destination = SentryLogsDestination(emitter: emitter)
        let bare = "no prefix here"

        destination.receive(level: .info, category: .general, message: bare)

        #expect(emitter.calls.first?.message == bare)
    }

    // MARK: - Helpers

    /// Mirrors the shape produced by `Logger.log(...)`.
    private func formatted(_ level: LogLevel, category: Category, body: String) -> String {
        "2026-06-02 12:34:56.789 SomeFile.swift:42 someFunction() [\(category.rawValue)/\(level)] \(body)"
    }
}

// MARK: - Test Doubles

/// File-local but referenced from a `@Test` parameter, so it cannot be `private`.
enum EmitterMethod: Sendable {
    case info, warn, error
}

private final class RecordingEmitter: SentryLogEmitter, @unchecked Sendable {
    struct Call {
        let method: EmitterMethod
        let message: String
        let attributes: [String: Any]
    }

    private let lock = NSLock()
    private var _calls: [Call] = []

    var calls: [Call] {
        lock.withLock { _calls }
    }

    func info(_ message: String, attributes: [String: Any]) {
        lock.withLock { _calls.append(Call(method: .info, message: message, attributes: attributes)) }
    }

    func warn(_ message: String, attributes: [String: Any]) {
        lock.withLock { _calls.append(Call(method: .warn, message: message, attributes: attributes)) }
    }

    func error(_ message: String, attributes: [String: Any]) {
        lock.withLock { _calls.append(Call(method: .error, message: message, attributes: attributes)) }
    }
}
