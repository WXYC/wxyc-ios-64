//
//  AsyncMessageTests.swift
//  Core
//
//  Tests for AsyncMessage notification handling.
//
//  Created by Jake Bromberg on 01/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Core

@Suite("AsyncNotificationMessage Tests")
struct AsyncMessageTests {

    @Test("Message can be posted and received")
    func postAndReceive() async {
        let center = NotificationCenter()
        let expectedData = "test-data"

        let subscribed = AsyncStream<Void>.makeStream()

        let task = Task<String?, Never> {
            for await message in center.messages(for: TestMessage.self, onSubscribed: {
                subscribed.continuation.yield()
                subscribed.continuation.finish()
            }) {
                return message.data
            }
            return nil
        }

        // Wait for observer to be registered
        for await _ in subscribed.stream { break }

        center.post(TestMessage(data: expectedData), subject: nil as TestService?)

        let received = await task.value
        #expect(received == expectedData)
    }

    @Test("Multiple messages are received in order")
    func multipleMessages() async {
        let center = NotificationCenter()
        let messages = ["first", "second", "third"]

        let subscribed = AsyncStream<Void>.makeStream()

        let task = Task {
            var received: [String] = []
            for await message in center.messages(for: TestMessage.self, onSubscribed: {
                subscribed.continuation.yield()
                subscribed.continuation.finish()
            }) {
                received.append(message.data)
                if received.count == messages.count {
                    break
                }
            }
            return received
        }

        // Wait for observer to be registered
        for await _ in subscribed.stream { break }

        for msg in messages {
            center.post(TestMessage(data: msg), subject: nil as TestService?)
        }

        let received = await task.value
        #expect(received == messages)
    }

    @Test("Subject filtering works correctly")
    func subjectFiltering() async {
        let center = NotificationCenter()
        let targetService = TestService()
        let otherService = TestService()

        let subscribed = AsyncStream<Void>.makeStream()

        let task = Task<String?, Never> {
            for await message in center.messages(of: targetService, for: TestMessage.self, onSubscribed: {
                subscribed.continuation.yield()
                subscribed.continuation.finish()
            }) {
                return message.data
            }
            return nil
        }

        // Wait for observer to be registered
        for await _ in subscribed.stream { break }

        // Post to other service first - should be ignored
        center.post(TestMessage(data: "wrong"), subject: otherService)

        // Post to target service - should be received
        center.post(TestMessage(data: "correct"), subject: targetService)

        let received = await task.value
        #expect(received == "correct")
    }

    @Test("makeMessage returns nil for invalid notification")
    func makeMessageReturnsNil() {
        let invalidNotification = Notification(name: TestMessage.name, object: nil, userInfo: nil)
        let message = TestMessage.makeMessage(invalidNotification)
        #expect(message == nil)
    }

    @Test("makeNotification creates valid notification")
    func makeNotificationCreatesValidNotification() {
        let message = TestMessage(data: "test")
        let service = TestService()
        let notification = TestMessage.makeNotification(message, object: service)

        #expect(notification.name == TestMessage.name)
        #expect(notification.object as AnyObject? === service)
        #expect(notification.userInfo?["data"] as? String == "test")
    }

    @Test("Cancellation stops receiving messages")
    func cancellationStopsReceiving() async {
        let center = NotificationCenter()
        let counter = Counter()

        let subscribed = AsyncStream<Void>.makeStream()
        let received = AsyncStream<Void>.makeStream()

        let task = Task {
            for await _ in center.messages(for: TestMessage.self, onSubscribed: {
                subscribed.continuation.yield()
                subscribed.continuation.finish()
            }) {
                counter.increment()
                received.continuation.yield()
            }
        }

        // Wait for observer to be registered
        for await _ in subscribed.stream { break }

        center.post(TestMessage(data: "one"), subject: nil as TestService?)

        // Wait for first message to be processed
        for await _ in received.stream { break }

        task.cancel()
        await task.value

        // This should not be received after cancellation
        center.post(TestMessage(data: "two"), subject: nil as TestService?)

        #expect(counter.value == 1)
    }
}

// MARK: - Test Fixtures

final class Counter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()

    var value: Int {
        lock.withLock { _value }
    }

    func increment() {
        lock.withLock { _value += 1 }
    }
}

final class TestService: Sendable {}

struct TestMessage: AsyncNotificationMessage, Sendable {
    typealias Subject = TestService

    static var name: Notification.Name { .init("Core.TestMessage") }

    let data: String

    static func makeMessage(_ notification: Notification) -> Self? {
        guard let data = notification.userInfo?["data"] as? String else { return nil }
        return Self(data: data)
    }

    static func makeNotification(_ message: Self, object: Subject?) -> Notification {
        Notification(name: name, object: object, userInfo: ["data": message.data])
    }
}
