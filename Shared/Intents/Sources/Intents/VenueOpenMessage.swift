//
//  VenueOpenMessage.swift
//  Intents
//
//  Typed "open this venue's shows" message posted by `OpenVenue.perform()`
//  (OT-C4), mirroring `ConcertOpenMessage` (#537). Delivered through the
//  shared `OpenMessage`/`MainActorNotificationMessage` machinery so
//  `Singletonia` can observe it without the app target reaching into
//  WXYCIntents' AppIntents surface, and route it to the On Tour tab's venue
//  filter.
//
//  Unlike `ConcertOpenMessage`, there is no universal-link form yet — a venue
//  has no public share URL, only the in-app `OpenVenue` intent — so this
//  carries just the backend venue id, with no `Source` distinction.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

public struct VenueOpenMessage: OpenMessage {
    public typealias Subject = NSObject

    public static let name = Notification.Name("org.wxyc.iphoneapp.openVenue")

    public struct Payload: NotificationPayload {
        public let venueID: Int

        public static func makePayload(userInfo: [AnyHashable: Any]?) -> Self? {
            guard let venueID = userInfo?["venueID"] as? Int else { return nil }
            return Self(venueID: venueID)
        }

        public var userInfoEntries: [AnyHashable: Any] {
            ["venueID": venueID]
        }
    }

    public let payload: Payload

    public init(payload: Payload) {
        self.payload = payload
    }

    public init(venueID: Int) {
        self.payload = Payload(venueID: venueID)
    }

    public var venueID: Int { payload.venueID }
}
