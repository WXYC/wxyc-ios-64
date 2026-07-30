//
//  TourAlert.swift
//  AppServices
//
//  The resolved content of a dev-only "artist on tour" lock-screen alert: the
//  concert it points at (also the de-dup key and notification identifier) plus
//  the ready-to-present title and body. Holds only value types and carries no
//  `Concerts` dependency, so it stays ungated across every platform the package
//  builds for; the decision that produces it (`TourAlertPlanner`) is gated.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A fully-resolved tour alert ready to hand to a ``TourAlertScheduling``.
public struct TourAlert: Equatable, Sendable {
    /// The upcoming concert this alert points at. Doubles as the per-session
    /// de-dup key and the notification request identifier (`tour-alert-<id>`).
    public let concertID: Int
    /// The on-air artist (from the playcut, not the concert headliner) the alert
    /// is about.
    public let artistName: String
    /// The presented notification title.
    public let title: String
    /// The presented notification body.
    public let body: String

    public init(concertID: Int, artistName: String, title: String, body: String) {
        self.concertID = concertID
        self.artistName = artistName
        self.title = title
        self.body = body
    }
}
