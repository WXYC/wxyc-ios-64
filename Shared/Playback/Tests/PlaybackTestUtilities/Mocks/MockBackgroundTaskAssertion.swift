//
//  MockBackgroundTaskAssertion.swift
//  Playback
//
//  Mock implementation of BackgroundTaskAssertionProtocol for testing
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@testable import PlaybackCore

/// Stands in for `UIApplication`'s background-task assertions.
///
/// No locking, unlike `MockAudioSession`: the seam is `@MainActor`-isolated
/// because `UIApplication` is, so every begin and end is already serialised on
/// the actor a test reads it from.
@MainActor
public final class MockBackgroundTaskAssertion: BackgroundTaskAssertionProtocol {

    /// One begin or end, in the order it happened. Ordering is the interesting
    /// part: an assertion taken for follow-on work has to begin *before* the one
    /// that scheduled it ends, or there is a window in which the app holds none
    /// and the system is free to suspend it.
    public enum Event: Equatable, Sendable {
        case begin(BackgroundTaskID, name: String)
        case end(BackgroundTaskID)

        public var isBegin: Bool {
            if case .begin = self { return true }
            return false
        }
    }

    public private(set) var events: [Event] = []

    /// Assertions begun but not yet ended.
    public private(set) var liveTasks: Set<BackgroundTaskID> = []

    /// Ends issued against an identifier that wasn't live — a double-end or an
    /// end of something never begun. `UIApplication` treats both as programming
    /// errors, so tests assert this stays zero.
    public private(set) var strayEndCount = 0

    /// When true, `beginTask` returns nil, modelling a system that declined to
    /// grant background execution.
    public var shouldDeclineToBegin = false

    private var nextRawValue = 1
    private var expirationHandlers: [BackgroundTaskID: @MainActor @Sendable () -> Void] = [:]

    public init() {}

    // MARK: - Observations

    public var activeCount: Int { liveTasks.count }
    public var beginCount: Int { events.filter(\.isBegin).count }
    public var endCount: Int { events.count - beginCount }

    // MARK: - BackgroundTaskAssertionProtocol

    public func beginTask(
        named name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskID? {
        guard !shouldDeclineToBegin else { return nil }
        let id = BackgroundTaskID(rawValue: nextRawValue)
        nextRawValue += 1
        liveTasks.insert(id)
        expirationHandlers[id] = expirationHandler
        events.append(.begin(id, name: name))
        return id
    }

    public func endTask(_ id: BackgroundTaskID) {
        guard liveTasks.remove(id) != nil else {
            strayEndCount += 1
            return
        }
        expirationHandlers[id] = nil
        events.append(.end(id))
    }

    // MARK: - Test Helpers

    /// Fires every live assertion's expiration handler, as the system does when
    /// the app's background time runs out. Expiration is app-wide, not per-task,
    /// so they all fire together here too.
    public func expireAll() {
        for handler in expirationHandlers.values {
            handler()
        }
    }

    public func reset() {
        events.removeAll()
        liveTasks.removeAll()
        expirationHandlers.removeAll()
        strayEndCount = 0
        shouldDeclineToBegin = false
        nextRawValue = 1
    }
}
