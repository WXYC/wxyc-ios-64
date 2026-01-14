//
//  MainActorMessageTests.swift
//  Core
//
//  Tests for MainActorMessage notification handling.
//
//  Created by Jake Bromberg on 01/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Core

@Suite("MainActorNotificationMessage Tests")
struct MainActorMessageTests {

    @Test("Message can be posted and received via AsyncSequence")
    @MainActor
    func postAndReceiveViaSequence() async {
        let center = NotificationCenter()
        let expectedTitle = "Test Title"

        let subscribed = AsyncStream<Void>.makeStream()

        let task = Task<String?, Never> { @MainActor in
            for await message in center.messages(for: UIUpdateMessage.self, onSubscribed: {
                subscribed.continuation.yield()
                subscribed.continuation.finish()
            }) {
                return message.title
            }
            return nil
        }

        // Wait for observer to be registered
        for await _ in subscribed.stream { break }

        center.post(UIUpdateMessage(title: expectedTitle), subject: nil as TestController?)

        let received = await task.value
        #expect(received == expectedTitle)
    }

    @Test("Message can be posted and received via addObserver")
    @MainActor
    func postAndReceiveViaObserver() async {
        let center = NotificationCenter()
        let expectedTitle = "Observer Title"

        let received = AsyncStream<String>.makeStream()

        let token = center.addMainActorObserver(
            for: UIUpdateMessage.self
        ) { message in
            received.continuation.yield(message.title)
            received.continuation.finish()
        }

        center.post(UIUpdateMessage(title: expectedTitle), subject: nil as TestController?)

        // Wait for notification delivery
        var receivedTitle: String?
        for await title in received.stream {
            receivedTitle = title
            break
        }

        #expect(receivedTitle == expectedTitle)
        center.removeObserver(token)
    }

    @Test("Subject filtering works correctly")
    @MainActor
    func subjectFiltering() async {
        let center = NotificationCenter()
        let targetController = TestController()
        let otherController = TestController()

        let subscribed = AsyncStream<Void>.makeStream()

        let task = Task<String?, Never> { @MainActor in
            for await message in center.messages(of: targetController, for: UIUpdateMessage.self, onSubscribed: {
                subscribed.continuation.yield()
                subscribed.continuation.finish()
            }) {
                return message.title
            }
            return nil
        }

        // Wait for observer to be registered
        for await _ in subscribed.stream { break }

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
    func multipleMessages() async {
        let center = NotificationCenter()
        let titles = ["first", "second", "third"]

        let subscribed = AsyncStream<Void>.makeStream()

        let task = Task { @MainActor in
            var received: [String] = []
            for await message in center.messages(for: UIUpdateMessage.self, onSubscribed: {
                subscribed.continuation.yield()
                subscribed.continuation.finish()
            }) {
                received.append(message.title)
                if received.count == titles.count {
                    break
                }
            }
            return received
        }

        // Wait for observer to be registered
        for await _ in subscribed.stream { break }

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
