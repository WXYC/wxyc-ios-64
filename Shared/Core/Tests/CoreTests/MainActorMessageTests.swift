//
//  MainActorMessageTests.swift
//  Core
//
//  Created by Jake Bromberg on 1/5/26.
//

import Testing
import Foundation
@testable import Core

@Suite("MainActorNotificationMessage Tests")
struct MainActorMessageTests {

    @Test("Message can be posted and received via AsyncSequence")
    @MainActor
    func postAndReceiveViaSequence() async throws {
        let center = NotificationCenter()
        let expectedTitle = "Test Title"

        let task = Task<String?, Never> { @MainActor in
            for await message in center.messages(for: UIUpdateMessage.self) {
                return message.title
            }
            return nil
        }

        // Give the observer time to register
        try await Task.sleep(for: .milliseconds(10))

        center.post(UIUpdateMessage(title: expectedTitle), subject: nil as TestController?)

        let received = await task.value
        #expect(received == expectedTitle)
    }

    @Test("Message can be posted and received via addObserver")
    @MainActor
    func postAndReceiveViaObserver() async throws {
        let center = NotificationCenter()
        let expectedTitle = "Observer Title"
        let receivedTitle = LockIsolated<String?>(nil)

        let token = center.addObserver(
            for: UIUpdateMessage.self
        ) { message in
            receivedTitle.setValue(message.title)
        }

        center.post(UIUpdateMessage(title: expectedTitle), subject: nil as TestController?)

        // Give time for notification delivery
        try await Task.sleep(for: .milliseconds(10))

        #expect(receivedTitle.value == expectedTitle)
        center.removeObserver(token)
    }

    @Test("Subject filtering works correctly")
    @MainActor
    func subjectFiltering() async throws {
        let center = NotificationCenter()
        let targetController = TestController()
        let otherController = TestController()

        let task = Task<String?, Never> { @MainActor in
            for await message in center.messages(of: targetController, for: UIUpdateMessage.self) {
                return message.title
            }
            return nil
        }

        try await Task.sleep(for: .milliseconds(10))

        // Post to other controller first - should be ignored
        center.post(UIUpdateMessage(title: "wrong"), subject: otherController)

        // Post to target controller - should be received
        center.post(UIUpdateMessage(title: "correct"), subject: targetController)

        let received = await task.value
        #expect(received == "correct")
    }

    @Test("makeMessage returns nil for invalid notification")
    @MainActor
    func makeMessageReturnsNil() {
        let invalidNotification = Notification(name: UIUpdateMessage.name, object: nil, userInfo: nil)
        let message = UIUpdateMessage.makeMessage(invalidNotification)
        #expect(message == nil)
    }

    @Test("makeNotification creates valid notification")
    @MainActor
    func makeNotificationCreatesValidNotification() {
        let message = UIUpdateMessage(title: "test")
        let controller = TestController()
        let notification = UIUpdateMessage.makeNotification(message, object: controller)

        #expect(notification.name == UIUpdateMessage.name)
        #expect(notification.object as AnyObject? === controller)
        #expect(notification.userInfo?["title"] as? String == "test")
    }

    @Test("Multiple messages are received in order")
    @MainActor
    func multipleMessages() async throws {
        let center = NotificationCenter()
        let titles = ["first", "second", "third"]

        let task = Task { @MainActor in
            var received: [String] = []
            for await message in center.messages(for: UIUpdateMessage.self) {
                received.append(message.title)
                if received.count == titles.count {
                    break
                }
            }
            return received
        }

        try await Task.sleep(for: .milliseconds(10))

        for title in titles {
            center.post(UIUpdateMessage(title: title), subject: nil as TestController?)
        }

        let received = await task.value
        #expect(received == titles)
    }
}

// MARK: - Test Fixtures

final class TestController: Sendable {}

struct UIUpdateMessage: MainActorNotificationMessage, Sendable {
    typealias Subject = TestController

    nonisolated static var name: Notification.Name { .init("Core.UIUpdateMessage") }

    let title: String

    static func makeMessage(_ notification: sending Notification) -> Self? {
        guard let title = notification.userInfo?["title"] as? String else { return nil }
        return Self(title: title)
    }

    @MainActor
    static func makeNotification(_ message: Self, object: Subject?) -> Notification {
        Notification(name: name, object: object, userInfo: ["title": message.title])
    }
}

/// Thread-safe wrapper for testing
final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        lock.withLock { _value }
    }

    func setValue(_ newValue: Value) {
        lock.withLock { _value = newValue }
    }
}
