//
//  PlaycutRoute.swift
//  Intents
//
//  Typed `open this playcut` message that flows through NotificationCenter via
//  the Shared/Core MainActorNotificationMessage machinery. Keeping this on a
//  typed protocol (rather than raw userInfo dicts) means observers can't
//  accidentally strip the phantom-typed id and the notification name is
//  guarded by the type itself — no cross-post collisions from unrelated
//  senders.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

public struct PlaycutOpenMessage: MainActorNotificationMessage {
    public typealias Subject = NotificationCenter

    public static let name = Notification.Name("org.wxyc.iphoneapp.openPlaycut")

    public let playcutID: PlaycutID

    public init(playcutID: PlaycutID) {
        self.playcutID = playcutID
    }

    public static func makeMessage(_ notification: sending Notification) -> Self? {
        guard notification.name == name,
              let raw = notification.userInfo?[Key.playcutID] as? String,
              let id = PlaycutID.entityIdentifier(for: raw)
        else {
            return nil
        }
        return Self(playcutID: id)
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: NotificationCenter?) -> Notification {
        Notification(
            name: name,
            object: object,
            userInfo: [Key.playcutID: message.playcutID.entityIdentifierString]
        )
    }

    private enum Key {
        static let playcutID = "playcutID"
    }
}
