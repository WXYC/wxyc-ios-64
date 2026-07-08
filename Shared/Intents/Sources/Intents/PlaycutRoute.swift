//
//  PlaycutRoute.swift
//  Intents
//
//  Broadcasts an "open this playcut" intent via NotificationCenter so the app's
//  URL scheme handler and any future in-app trigger share a single delivery
//  channel. F1 lands the emitter; the consumer that maps the id to a detail
//  view lands in F3 when the playcut cache exists.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum PlaycutRoute {
    /// Posted when a `wxyc://playcut/<id>` deep link is opened. Subscribe on the
    /// default `NotificationCenter` and read the id via `playcutID(from:)`.
    public static let openNotification = Notification.Name("org.wxyc.iphoneapp.openPlaycut")

    static let playcutIDUserInfoKey = "playcutID"

    /// Publishes an intent to open the given playcut on `center`. Defaults to
    /// `.default` so the URL handler can call it without threading a center.
    public static func broadcastOpen(
        playcutID: UInt64,
        using center: NotificationCenter = .default
    ) {
        center.post(
            name: openNotification,
            object: nil,
            userInfo: [playcutIDUserInfoKey: playcutID]
        )
    }

    /// Reads a `Playcut.id` from an `openNotification` userInfo dictionary.
    /// Returns `nil` if the notification originated from a different source.
    public static func playcutID(from notification: Notification) -> UInt64? {
        notification.userInfo?[playcutIDUserInfoKey] as? UInt64
    }
}
