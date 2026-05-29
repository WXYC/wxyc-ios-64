//
//  UIApplicationMessages.swift
//  PlaybackCore
//
//  Typed MainActorNotificationMessage wrappers around
//  UIApplication.didEnterBackgroundNotification and willEnterForegroundNotification.
//  Empty payloads; the message identity carries the signal.
//
//  Created by Jake Bromberg on 05/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS)
import Core
import Foundation
import UIKit

/// Message for `UIApplication.didEnterBackgroundNotification`. Empty payload.
public struct AppDidEnterBackgroundMessage: MainActorNotificationMessage {
    public typealias Subject = UIApplication

    public static var name: Notification.Name { UIApplication.didEnterBackgroundNotification }

    public init() {}

    public static func makeMessage(_ notification: sending Notification) -> Self? { Self() }

    @MainActor
    public static func makeNotification(_ message: Self, object: UIApplication?) -> Notification {
        Notification(name: name, object: object)
    }
}

/// Message for `UIApplication.willEnterForegroundNotification`. Empty payload.
public struct AppWillEnterForegroundMessage: MainActorNotificationMessage {
    public typealias Subject = UIApplication

    public static var name: Notification.Name { UIApplication.willEnterForegroundNotification }

    public init() {}

    public static func makeMessage(_ notification: sending Notification) -> Self? { Self() }

    @MainActor
    public static func makeNotification(_ message: Self, object: UIApplication?) -> Notification {
        Notification(name: name, object: object)
    }
}
#endif
