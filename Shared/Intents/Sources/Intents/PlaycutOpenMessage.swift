//
//  PlaycutOpenMessage.swift
//  Intents
//
//  Typed "open this playcut" message that flows through NotificationCenter via
//  the shared `OpenMessage`/`MainActorNotificationMessage` machinery. Because
//  the payload is a phantom-typed `PlaycutID`, observers can't accidentally
//  strip the type and the notification name is guarded by the protocol — no
//  cross-post collisions from unrelated senders.
//
//  Subject is `NSObject` because the message has no natural emitter to filter
//  by (the URL handler and OpenPlaycut are both "the app"). Callers pass `nil`.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

public struct PlaycutOpenMessage: OpenMessage {
    public typealias Subject = NSObject

    public static let name = Notification.Name("org.wxyc.iphoneapp.openPlaycut")

    public struct Payload: NotificationPayload {
        public let playcutID: PlaycutID

        public static func makePayload(userInfo: [AnyHashable: Any]?) -> Self? {
            guard let raw = userInfo?["playcutID"] as? String,
                  let playcutID = PlaycutID.entityIdentifier(for: raw)
            else {
                return nil
            }
            return Self(playcutID: playcutID)
        }

        public var userInfoEntries: [AnyHashable: Any] {
            ["playcutID": playcutID.entityIdentifierString]
        }
    }

    public let payload: Payload

    public init(payload: Payload) {
        self.payload = payload
    }

    public init(playcutID: PlaycutID) {
        self.payload = Payload(playcutID: playcutID)
    }

    public var playcutID: PlaycutID { payload.playcutID }
}
