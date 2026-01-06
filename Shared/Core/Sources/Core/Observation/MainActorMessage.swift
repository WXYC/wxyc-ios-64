//
//  MainActorMessage.swift
//  Core
//
//  Created by Jake Bromberg on 1/5/26.
//

@preconcurrency import Foundation

// MARK: - MainActorNotificationMessage Protocol

/// A backport of `NotificationCenter.MainActorMessage` for iOS versions prior to iOS 26.
///
/// This protocol enables type-safe notifications that are bound to the main actor.
/// Observers are guaranteed to be called on the main thread. On iOS 26+, consider
/// using the native `NotificationCenter.MainActorMessage` protocol instead.
///
/// Use `MainActorNotificationMessage` when your notification handling must occur
/// on the main thread (e.g., UI updates). For notifications that can be handled
/// on any thread, use `AsyncNotificationMessage` instead.
///
/// Example usage:
/// ```swift
/// struct UIUpdateMessage: MainActorNotificationMessage {
///     typealias Subject = MyViewController
///     static var name: Notification.Name { .init("UIUpdateMessage") }
///
///     let newTitle: String
///
///     static func makeMessage(_ notification: Notification) -> Self? {
///         guard let title = notification.userInfo?["title"] as? String else { return nil }
///         return Self(newTitle: title)
///     }
///
///     static func makeNotification(_ message: Self, object: Subject?) -> Notification {
///         Notification(name: name, object: object, userInfo: ["title": message.newTitle])
///     }
/// }
/// ```
public protocol MainActorNotificationMessage: Sendable {
    /// The type of object that can be the subject of this message.
    associatedtype Subject

    /// The notification name used for posting and observing this message type.
    nonisolated static var name: Notification.Name { get }

    /// Converts a traditional `Notification` to this message type.
    /// Returns `nil` if the notification cannot be converted.
    /// This method is called on the main thread.
    static func makeMessage(_ notification: sending Notification) -> Self?

    /// Converts this message to a traditional `Notification`.
    @MainActor
    static func makeNotification(_ message: Self, object: Subject?) -> Notification
}

// MARK: - NotificationCenter Extensions for MainActorMessage

public extension NotificationCenter {
    /// Posts a main actor message with an object subject.
    ///
    /// - Parameters:
    ///   - message: The message to post.
    ///   - subject: The object that is the subject of this message.
    @MainActor
    func post<M: MainActorNotificationMessage>(_ message: M, subject: M.Subject?) where M.Subject: AnyObject {
        let notification = M.makeNotification(message, object: subject)
        post(notification)
    }

    /// Posts a main actor message with a metatype subject.
    ///
    /// - Parameters:
    ///   - message: The message to post.
    ///   - subject: The metatype that is the subject of this message.
    @MainActor
    func post<M: MainActorNotificationMessage>(_ message: M, subject: M.Subject.Type) {
        let notification = M.makeNotification(message, object: nil)
        post(notification)
    }

    /// Adds an observer for a main actor message type.
    ///
    /// The observer closure is guaranteed to be called on the main actor.
    ///
    /// - Note: Named `addMainActorObserver` to avoid collision with iOS 26's native
    ///   `addObserver(of:for:using:)` method.
    ///
    /// - Parameters:
    ///   - subject: The object to filter messages by, or `nil` to receive all messages of this type.
    ///   - messageType: The type of message to observe.
    ///   - observer: A closure called when a matching message is posted.
    /// - Returns: An observation token. Remove the observer by calling `removeObserver(_:)` with this token,
    ///   or let the token be deallocated to automatically remove the observer.
    @MainActor
    func addMainActorObserver<M: MainActorNotificationMessage>(
        of subject: M.Subject? = nil,
        for messageType: M.Type,
        using observer: @escaping @MainActor (M) -> Void
    ) -> any NSObjectProtocol where M.Subject: AnyObject {
        addObserver(
            forName: M.name,
            object: subject,
            queue: .main
        ) { notification in
            if let message = M.makeMessage(notification) {
                MainActor.assumeIsolated {
                    observer(message)
                }
            }
        }
    }

    /// Returns an async sequence of main actor messages matching the given type and optional subject.
    ///
    /// Messages are delivered on the main actor.
    ///
    /// - Parameters:
    ///   - subject: The object to filter messages by, or `nil` to receive all messages of this type.
    ///   - messageType: The type of message to observe.
    /// - Returns: An `AsyncSequence` that yields messages as they are posted.
    func messages<M: MainActorNotificationMessage>(
        of subject: M.Subject? = nil,
        for messageType: M.Type
    ) -> MainActorNotificationMessageSequence<M> where M.Subject: AnyObject {
        MainActorNotificationMessageSequence(center: self, subject: subject)
    }

    /// Returns an async sequence of main actor messages matching the given type.
    ///
    /// Messages are delivered on the main actor.
    ///
    /// - Parameter messageType: The type of message to observe.
    /// - Returns: An `AsyncSequence` that yields messages as they are posted.
    func messages<M: MainActorNotificationMessage>(
        for messageType: M.Type
    ) -> MainActorNotificationMessageSequence<M> where M.Subject: AnyObject {
        MainActorNotificationMessageSequence(center: self, subject: nil)
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
    func messages<M: MainActorNotificationMessage>(
        of subject: M.Subject? = nil,
        for messageType: M.Type,
        onSubscribed: @escaping () -> Void
    ) -> MainActorNotificationMessageSequence<M> where M.Subject: AnyObject {
        var sequence = MainActorNotificationMessageSequence<M>(center: self, subject: subject)
        sequence.onSubscribed = onSubscribed
        return sequence
    }
}

// MARK: - MainActorNotificationMessageSequence

/// An `AsyncSequence` that yields main actor notification messages as they are posted.
public struct MainActorNotificationMessageSequence<M: MainActorNotificationMessage>: AsyncSequence
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
                queue: .main
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

extension Notification: @unchecked @retroactive Sendable { }
