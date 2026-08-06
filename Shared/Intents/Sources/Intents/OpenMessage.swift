//
//  OpenMessage.swift
//  Intents
//
//  Shared plumbing for the "open this thing" family of
//  `MainActorNotificationMessage`s posted by the `Open*` intents
//  (`ConcertOpenMessage`, `VenueOpenMessage`, `PlaycutOpenMessage`). Each of
//  those was previously a clone: the same notification-name guard in
//  `makeMessage`, the same `Notification` builder in `makeNotification`,
//  differing only in the userInfo keys and the payload's shape. `OpenMessage`
//  hoists both into one default implementation over a `NotificationPayload`
//  that owns its own userInfo keys, so a conforming type is left to declare
//  only its `name` and its `Payload`.
//
//  `postOpenMessage(_:)` is the matching posting helper: every `Open*`
//  intent's `perform()` hands its target off to the in-app observer that
//  does the actual navigation the same way (post to `.default`, no subject),
//  so that call collapses to one line per intent too.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

/// A value that round-trips through a `Notification`'s `userInfo`
/// dictionary — the payload half of an `OpenMessage`. Conforming types own
/// the userInfo key(s) they read and write, so a message with more than one
/// field (like `ConcertOpenMessage`'s id + `Source`) fits the same protocol
/// as a single-field one.
public protocol NotificationPayload: Sendable {
    /// Reconstructs the payload from a notification's `userInfo` dictionary.
    /// Returns `nil` when a required entry is missing or malformed.
    static func makePayload(userInfo: [AnyHashable: Any]?) -> Self?

    /// The `userInfo` entries this payload contributes when its message posts.
    var userInfoEntries: [AnyHashable: Any] { get }
}

/// A `MainActorNotificationMessage` that's a thin, typed wrapper around a
/// `NotificationPayload`. Conforming types need only declare `name`,
/// `Payload`, and the `payload` <-> message bridging — `makeMessage` and
/// `makeNotification` come from this protocol's extension.
public protocol OpenMessage: MainActorNotificationMessage where Subject == NSObject {
    associatedtype Payload: NotificationPayload

    var payload: Payload { get }

    init(payload: Payload)
}

extension OpenMessage {
    public static func makeMessage(_ notification: sending Notification) -> Self? {
        guard notification.name == name,
              let payload = Payload.makePayload(userInfo: notification.userInfo)
        else {
            return nil
        }
        return Self(payload: payload)
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: NSObject?) -> Notification {
        Notification(name: name, object: object, userInfo: message.payload.userInfoEntries)
    }
}

/// Posts an `OpenMessage` to `NotificationCenter.default` with no subject —
/// the single call every `Open*` intent's `perform()` makes to hand its
/// target off to the in-app observer that does the actual navigation.
@MainActor
public func postOpenMessage<M: OpenMessage>(_ message: M) {
    NotificationCenter.default.post(message, subject: nil)
}
