//
//  PlaycutOpenMessage.swift
//  Intents
//
//  Typed "open this playcut" message that flows through NotificationCenter via
//  the Shared/Core MainActorNotificationMessage machinery. Because the payload
//  is a phantom-typed `PlaycutID`, observers can't accidentally strip the type
//  and the notification name is guarded by the protocol — no cross-post
//  collisions from unrelated senders.
//
//  Subject is `NSObject` because the message has no natural emitter to filter
//  by (the URL handler and OpenPlaycut are both "the app"). Callers pass `nil`.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

public struct PlaycutOpenMessage: MainActorNotificationMessage {
    public typealias Subject = NSObject

    public static let name = Notification.Name("org.wxyc.iphoneapp.openPlaycut")

    public let playcutID: PlaycutID

    public init(playcutID: PlaycutID) {
        self.playcutID = playcutID
    }

    public static func makeMessage(_ notification: sending Notification) -> Self? {
        guard notification.name == name,
              let raw = notification.userInfo?["playcutID"] as? String,
              let id = PlaycutID.entityIdentifier(for: raw)
        else {
            return nil
        }
        return Self(playcutID: id)
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: NSObject?) -> Notification {
        Notification(
            name: name,
            object: object,
            userInfo: ["playcutID": message.playcutID.entityIdentifierString]
        )
    }
}
