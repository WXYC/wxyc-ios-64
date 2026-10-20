//
//  StructuredPostHogAnalyticsTests.swift
//  Analytics
//
//  Verifies build_type stamping on every captured event.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

@Suite("StructuredPostHogAnalytics exception capture")
struct StructuredPostHogAnalyticsExceptionTests {

    @Test("captureReportedError sends the error event and the exception, both carrying context and category")
    func reportedErrorFiresEventAndException() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "Debug")
        let error = NSError(domain: "TestDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])

        sut.captureReportedError(error, context: "ctx", category: "Network", additionalData: ["k": "v"])

        #expect(captured.events.map(\.name) == ["error"])
        let exception = try #require(captured.exceptions.first)
        #expect((exception.error as NSError).code == 7)
        #expect(exception.properties?["context"] as? String == "ctx")
        #expect(exception.properties?["category"] as? String == "Network")
        #expect(exception.properties?["k"] as? String == "v")
        #expect(exception.properties?["build_type"] as? String == "Debug")
    }
}

@Suite("StructuredPostHogAnalytics exception gate")
struct StructuredPostHogAnalyticsExceptionGateTests {

    private func makeSUT(clock: ManualClock) -> (sut: StructuredPostHogAnalytics, client: CapturingPostHogClient) {
        let client = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(
            client: client,
            buildType: "Debug",
            exceptionGate: ExceptionGate(now: { clock.now })
        )
        return (sut, client)
    }

    private func error(_ code: Int) -> NSError {
        NSError(domain: "TestDomain", code: code)
    }

    @Test("A repeat of the same error inside 60 seconds is not sent")
    func repeatIsNotSent() {
        let (sut, client) = makeSUT(clock: ManualClock())

        sut.captureException(error(1), properties: nil)
        sut.captureException(error(1), properties: nil)

        #expect(client.exceptions.count == 1)
    }

    /// Stands in for the `NSURLError` subclass that URLSession hands back, whose description
    /// embeds per-instance addresses and timings.
    private final class SubclassedError: NSError, @unchecked Sendable {
        let note: String

        init(domain: String, code: Int, note: String) {
            self.note = note
            super.init(domain: domain, code: code, userInfo: ["note": note])
        }

        required init?(coder: NSCoder) {
            fatalError("not used")
        }

        override var description: String {
            "\(domain) \(code) \(note)"
        }
    }

    @Test("NSError subclasses with the same domain and code dedupe despite different descriptions")
    func nsErrorSubclassDedupesOnDomainAndCode() {
        let (sut, client) = makeSUT(clock: ManualClock())

        sut.captureException(SubclassedError(domain: NSURLErrorDomain, code: -1001, note: "0x7b0b7c8ea0 163ms"), properties: nil)
        sut.captureException(SubclassedError(domain: NSURLErrorDomain, code: -1001, note: "0x7b0b7c8d50 0ms"), properties: nil)
        sut.captureException(SubclassedError(domain: NSURLErrorDomain, code: -1009, note: "0x7b0b7c8d50 0ms"), properties: nil)

        #expect(client.exceptions.count == 2)
    }

    @Test("The same domain and code with a different context is a different key")
    func contextSeparatesKeys() {
        let (sut, client) = makeSUT(clock: ManualClock())

        sut.captureException(error(1), properties: ["context": "playlist"])
        sut.captureException(error(1), properties: ["context": "stream"])

        #expect(client.exceptions.count == 2)
    }

    @Test("An explicit fingerprint replaces the message as the dedupe key")
    func fingerprintKeysTheDedupe() {
        let (sut, client) = makeSUT(clock: ManualClock())

        sut.captureException(error(1), properties: ["$exception_fingerprint": "retry-loop"])
        sut.captureException(error(2), properties: ["$exception_fingerprint": "retry-loop"])

        #expect(client.exceptions.count == 1)
    }

    @Test("The twenty-first distinct error is not sent")
    func burstIsCapped() {
        let (sut, client) = makeSUT(clock: ManualClock())

        for code in 0..<25 {
            sut.captureException(error(code), properties: nil)
        }

        #expect(client.exceptions.count == 20)
    }

    @Test("An admitted exception is still stamped with build_type")
    func admittedExceptionKeepsBuildType() throws {
        let (sut, client) = makeSUT(clock: ManualClock())

        sut.captureException(error(1), properties: nil)

        let sent = try #require(client.exceptions.first)
        #expect(sent.properties?["build_type"] as? String == "Debug")
    }

    @Test("A MetricKit crash ExceptionEvent still goes out when the bucket is empty")
    func metricKitCrashBypassesGate() throws {
        let (sut, client) = makeSUT(clock: ManualClock())
        for code in 0..<25 {
            sut.captureException(error(code), properties: nil)
        }

        let crash = ExceptionEvent(
            source: "metrickit",
            diagnosticKind: "crash",
            level: "fatal",
            exceptionList: [["type": "EXC_BAD_ACCESS"]]
        )
        sut.capture(crash)
        sut.capture(crash)

        #expect(client.events.map(\.name) == ["$exception", "$exception"])
    }
}

@Suite("StructuredPostHogAnalytics build_type stamping")
struct StructuredPostHogAnalyticsTests {

    struct PlainEvent: AnalyticsEvent {
        static let name = "plain_event"
        var properties: [String: Any]? { ["foo": "bar"] }
    }

    struct EventWithTypedBuildType: AnalyticsEvent {
        static let name = "event_with_typed_build_type"
        var properties: [String: Any]? { ["build_type": "typed_wins"] }
    }

    struct EmptyEvent: AnalyticsEvent {
        static let name = "empty_event"
        var properties: [String: Any]? { nil }
    }

    @Test("Plain event gets build_type stamped from initializer")
    func plainEventGetsBuildTypeStamped() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "TestFlight")

        sut.capture(PlainEvent())

        let last = try #require(captured.events.last)
        #expect(last.name == "plain_event")
        #expect(last.properties?["foo"] as? String == "bar")
        #expect(last.properties?["build_type"] as? String == "TestFlight")
    }

    @Test("Typed event property wins on collision with stamped build_type")
    func typedEventBuildTypeWinsOverStamp() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "Release")

        sut.capture(EventWithTypedBuildType())

        let last = try #require(captured.events.last)
        #expect(last.properties?["build_type"] as? String == "typed_wins")
    }

    @Test("Empty-property event still gets build_type stamped")
    func emptyEventGetsBuildTypeStamped() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "Debug")

        sut.capture(EmptyEvent())

        let last = try #require(captured.events.last)
        #expect(last.properties?["build_type"] as? String == "Debug")
    }
}

/// Recording double for `PostHogClientProtocol`, shared by this suite and
/// `StructuredPostHogAnalyticsConcurrencyTests`.
///
/// Synchronized so the recorder itself can't be what races: the concurrency
/// suite hammers one instance from a task group, and the `Sendable` refinement
/// #309 put on `PostHogClientProtocol` requires conformers to mean it.
///
/// `NSLock` rather than `Mutex`, deliberately. The repo default is `Mutex`
/// (see `MockStructuredAnalytics`, #816), but that only works when the guarded
/// value is `Sendable`. `Captured.properties` is `[String: Any]?` — PostHog's
/// own property shape — so `Mutex<[Captured]>` cannot hand a snapshot back out:
/// `withLock`'s `inout sending Value` makes any value derived from the payload
/// task-isolated, and the getter fails to compile with "'inout sending'
/// parameter '$0' cannot be task-isolated at end of function". The only way to
/// reach `Mutex` here is to declare `Captured: @unchecked Sendable`, which
/// would be a worse lie than the one this annotation makes honest.
final class CapturingPostHogClient: PostHogClientProtocol, @unchecked Sendable {
    struct Captured {
        let name: String
        let properties: [String: Any]?
    }

    private let lock = NSLock()
    private var _events: [Captured] = []

    /// A snapshot of everything captured so far, in capture order.
    var events: [Captured] {
        lock.withLock { _events }
    }

    func capture(_ name: String, properties: [String: Any]?) {
        lock.withLock {
            _events.append(Captured(name: name, properties: properties))
        }
    }

    /// Exceptions recorded by `captureException`, in capture order.
    var exceptions: [(error: any Error, properties: [String: Any]?)] {
        lock.withLock { _exceptions }
    }

    private var _exceptions: [(error: any Error, properties: [String: Any]?)] = []

    func captureException(_ error: any Error, properties: [String: Any]?) {
        lock.withLock {
            _exceptions.append((error, properties))
        }
    }
}
