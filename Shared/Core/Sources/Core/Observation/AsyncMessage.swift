//
//  AsyncMessage.swift
//  Core
//
//  Base protocol for type-safe async notification messages.
//
//  Created by Jake Bromberg on 01/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

@preconcurrency import Foundation

// MARK: - AsyncNotificationMessage Protocol

/// A backport of `NotificationCenter.AsyncMessage` for iOS versions prior to iOS 26.
///
/// This protocol enables type-safe, concurrency-safe notifications that can be
/// observed via `AsyncSequence`. On iOS 26+, consider using the native
/// `NotificationCenter.AsyncMessage` protocol instead.
///
/// Example usage:
/// ```swift
/// struct MyMessage: AsyncNotificationMessage {
///     typealias Subject = MyService
///     static var name: Notification.Name { .init("MyMessage") }
///
///     let data: String
///
///     static func makeMessage(_ notification: Notification) -> Self? {
///         guard let data = notification.userInfo?["data"] as? String else { return nil }
///         return Self(data: data)
///     }
///
///     static func makeNotification(_ message: Self, object: Subject?) -> Notification {
///         Notification(name: name, object: object, userInfo: ["data": message.data])
///     }
/// }
/// ```
public protocol AsyncNotificationMessage: Sendable {
    /// The type of object that can be the subject of this message.
    associatedtype Subject

    /// The notification name used for posting and observing this message type.
    static var name: Notification.Name { get }

    /// Converts a traditional `Notification` to this message type.
    /// Returns `nil` if the notification cannot be converted.
    static func makeMessage(_ notification: Notification) -> Self?

    /// Converts this message to a traditional `Notification`.
    static func makeNotification(_ message: Self, object: Subject?) -> Notification
}

// MARK: - NotificationCenter Extensions

extension NotificationCenter {
    /// Posts an async message with an object subject.
    ///
    /// - Parameters:
    ///   - message: The message to post.
    ///   - subject: The object that is the subject of this message.
    public func post<M: AsyncNotificationMessage>(_ message: M, subject: M.Subject?) where M.Subject: AnyObject {
        let notification = M.makeNotification(message, object: subject)
        post(notification)
    }

    /// Posts an async message with a metatype subject.
    ///
    /// - Parameters:
    ///   - message: The message to post.
    ///   - subject: The metatype that is the subject of this message.
    public func post<M: AsyncNotificationMessage>(_ message: M, subject: M.Subject.Type) {
        let notification = M.makeNotification(message, object: nil)
        post(notification)
    }

    /// Returns an async sequence of messages matching the given type and optional subject.
    ///
    /// - Parameters:
    ///   - subject: The object to filter messages by, or `nil` to receive all messages of this type.
    ///   - messageType: The type of message to observe.
    /// - Returns: An `AsyncSequence` that yields messages as they are posted.
    public func messages<M: AsyncNotificationMessage>(
        of subject: M.Subject? = nil,
        for messageType: M.Type
    ) -> AsyncNotificationMessageSequence<M> where M.Subject: AnyObject {
        AsyncNotificationMessageSequence(center: self, subject: subject)
    }

    /// Returns an async sequence of messages matching the given type.
    ///
    /// - Parameter messageType: The type of message to observe.
    /// - Returns: An `AsyncSequence` that yields messages as they are posted.
    public func messages<M: AsyncNotificationMessage>(
        for messageType: M.Type
    ) -> AsyncNotificationMessageSequence<M> where M.Subject: AnyObject {
        AsyncNotificationMessageSequence(center: self, subject: nil)
    }

    /// Returns an async sequence with a callback that fires when the observer is registered.
    ///
    /// This variant is useful for tests that need to synchronize with observer registration.
    ///
    /// - Parameters:
    ///   - subject: The object to filter messages by, or `nil` to receive all messages.
    ///   - messageType: The type of message to observe.
    ///   - onSubscribed: Callback fired when the observer is registered.
    /// - Returns: An `AsyncSequence` that yields messages as they are posted.
    public func messages<M: AsyncNotificationMessage>(
        of subject: M.Subject? = nil,
        for messageType: M.Type,
        onSubscribed: @escaping () -> Void
    ) -> AsyncNotificationMessageSequence<M> where M.Subject: AnyObject {
        var sequence = AsyncNotificationMessageSequence<M>(center: self, subject: subject)
        sequence.onSubscribed = onSubscribed
        return sequence
    }
}

// MARK: - AsyncNotificationMessageSequence

/// An `AsyncSequence` that yields notification messages as they are posted.
public struct AsyncNotificationMessageSequence<M: AsyncNotificationMessage>: AsyncSequence
    where M.Subject: AnyObject
{
    public typealias Element = M

    private let center: NotificationCenter
    private let subject: M.Subject?

    /// Internal callback fired when observer is registered. Used by tests for synchronization.
    var onSubscribed: (() -> Void)?

    init(center: NotificationCenter, subject: M.Subject?) {
        self.center = center
        self.subject = subject
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(center: center, subject: subject, onSubscribed: onSubscribed)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncStream<M>.Iterator

        init(center: NotificationCenter, subject: M.Subject?, onSubscribed: (() -> Void)?) {
            let (stream, continuation) = AsyncStream<M>.makeStream(bufferingPolicy: .bufferingNewest(100))

            let observation = center.addObserver(
                forName: M.name,
                object: subject,
                queue: nil
            ) { notification in
                if let message = M.makeMessage(notification) {
                    continuation.yield(message)
                }
            }

            // Signal that observer is now registered
            onSubscribed?()

            continuation.onTermination = { _ in
                center.removeObserver(observation)
            }

            self.iterator = stream.makeAsyncIterator()
        }

        public mutating func next() async -> M? {
            await iterator.next()
        }
    }
}
