//
//  ApplicationWillTerminateMessage.swift
//  Core
//
//  Notification message for app termination events.
//
//  Created by Jake Bromberg on 01/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(UIKit) && !os(watchOS)
import Foundation
import UIKit

public struct ApplicationWillTerminateMessage: MainActorNotificationMessage {
    // UIKit posts this with the UIApplication instance as the notification object.
    public typealias Subject = UIApplication

    // Bridge to the existing Notification.Name
    public nonisolated static var name: Notification.Name { UIApplication.willTerminateNotification }

    // Convert Notification -> Message
    public static func makeMessage(_ notification: sending Notification) -> Self? {
        guard notification.name == name else { return nil }
        return Self()
    }

    // Convert Message -> Notification (mostly useful for testing / interoperability)
    @MainActor
    public static func makeNotification(_ message: Self, object: Subject?) -> Notification {
        Notification(name: name, object: object)
    }
}
#endif
