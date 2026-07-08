//
//  PlaycutRouteTests.swift
//  WXYCIntents
//
//  Verifies the NotificationCenter delivery channel that carries "open this
//  playcut" intents between the URL scheme handler and any future consumer.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import WXYCIntents

@Suite("PlaycutRoute")
struct PlaycutRouteTests {
    @Test("broadcastOpen posts a notification carrying the playcut id")
    func broadcastOpenPostsNotification() async throws {
        let center = NotificationCenter()
        let received = LockedBox<UInt64?>(value: nil)

        let observer = center.addObserver(
            forName: PlaycutRoute.openNotification,
            object: nil,
            queue: nil
        ) { notification in
            received.set(PlaycutRoute.playcutID(from: notification))
        }
        defer { center.removeObserver(observer) }

        PlaycutRoute.broadcastOpen(playcutID: 42, using: center)

        #expect(received.get() == 42)
    }

    @Test("playcutID(from:) returns nil for a notification with no matching userInfo")
    func playcutIDReturnsNilForUnrelatedNotification() {
        let notification = Notification(
            name: PlaycutRoute.openNotification,
            object: nil,
            userInfo: ["unrelated": "value"]
        )

        #expect(PlaycutRoute.playcutID(from: notification) == nil)
    }
}

/// A tiny thread-safe box for capturing a value from a NotificationCenter observer.
/// The observer runs synchronously when `queue: nil`, so no locking is strictly needed,
/// but the box keeps the reference-semantics explicit for future readers.
private final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}
