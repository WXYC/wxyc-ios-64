//
//  PostHogLogsDestinationTests.swift
//  WXYC
//
//  Tests for PostHogLogsDestination: warning-and-above filtering, prefix
//  stripping, category-attribute forwarding, and per-level routing.
//
//  Created by Jake Bromberg on 10/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Logger
@testable import WXYC

@Suite("PostHogLogsDestination")
struct PostHogLogsDestinationTests {

    @Test(".debug and .info are dropped before reaching the emitter", arguments: [LogLevel.debug, LogLevel.info])
    func belowWarningIsDropped(level: LogLevel) {
        let emitter = RecordingPostHogEmitter()
        let destination = PostHogLogsDestination(emitter: emitter)

        destination.receive(
            level: level,
            category: .general,
            message: formatted(level, category: .general, body: "noisy")
        )

        #expect(emitter.calls.isEmpty)
    }

    @Test(
        ".warning / .error route to the matching emitter method",
        arguments: [
            (LogLevel.warning, PostHogEmitterMethod.warn),
            (LogLevel.error, PostHogEmitterMethod.error)
        ]
    )
    func levelsRouteToMatchingMethod(level: LogLevel, expectedMethod: PostHogEmitterMethod) {
        let emitter = RecordingPostHogEmitter()
        let destination = PostHogLogsDestination(emitter: emitter)

        destination.receive(
            level: level,
            category: .playback,
            message: formatted(level, category: .playback, body: "real body")
        )

        #expect(emitter.calls.count == 1)
        #expect(emitter.calls.first?.method == expectedMethod)
    }

    @Test("category is forwarded as an attribute")
    func categoryForwardedAsAttribute() throws {
        let emitter = RecordingPostHogEmitter()
        let destination = PostHogLogsDestination(emitter: emitter)

        destination.receive(
            level: .warning,
            category: .network,
            message: formatted(.warning, category: .network, body: "DNS slow")
        )

        let call = try #require(emitter.calls.first)
        #expect(call.attributes["category"] as? String == LogCategory.network.rawValue)
    }

    @Test("formatted prefix is stripped, leaving only the developer body")
    func prefixIsStripped() {
        let emitter = RecordingPostHogEmitter()
        let destination = PostHogLogsDestination(emitter: emitter)

        let body = "Stream stalled after 12s"
        destination.receive(
            level: .error,
            category: .playback,
            message: formatted(.error, category: .playback, body: body)
        )

        #expect(emitter.calls.first?.message == body)
    }

    // MARK: - Helpers

    /// Mirrors the shape produced by `Logger.log(...)`.
    private func formatted(_ level: LogLevel, category: LogCategory, body: String) -> String {
        "2026-06-02 12:34:56.789 SomeFile.swift:42 someFunction() [\(category.rawValue)/\(level)] \(body)"
    }
}

// MARK: - Test Doubles

/// File-local but referenced from a `@Test` parameter, so it cannot be `private`.
enum PostHogEmitterMethod: Sendable {
    case warn, error
}

private nonisolated final class RecordingPostHogEmitter: PostHogLogEmitter, @unchecked Sendable {
    struct Call {
        let method: PostHogEmitterMethod
        let message: String
        let attributes: [String: Any]
    }

    private let lock = NSLock()
    private var _calls: [Call] = []

    var calls: [Call] {
        lock.withLock { _calls }
    }

    func warn(_ message: String, attributes: [String: Any]) {
        lock.withLock { _calls.append(Call(method: .warn, message: message, attributes: attributes)) }
    }

    func error(_ message: String, attributes: [String: Any]) {
        lock.withLock { _calls.append(Call(method: .error, message: message, attributes: attributes)) }
    }
}
