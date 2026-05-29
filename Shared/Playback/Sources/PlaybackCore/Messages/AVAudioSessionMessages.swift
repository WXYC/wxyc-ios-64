//
//  AVAudioSessionMessages.swift
//  PlaybackCore
//
//  Typed MainActorNotificationMessage wrappers around
//  AVAudioSession.interruptionNotification and AVAudioSession.routeChangeNotification.
//  Player controllers observe these via NotificationCenter.addMainActorObserver
//  instead of decoding raw userInfo dictionaries at the call site.
//
//  Created by Jake Bromberg on 05/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS)
import AVFoundation
import Core
import Foundation

/// Message for `AVAudioSession.interruptionNotification`.
public struct InterruptionMessage: MainActorNotificationMessage {
    public typealias Subject = AVAudioSession

    public static var name: Notification.Name { AVAudioSession.interruptionNotification }

    public let type: AVAudioSession.InterruptionType
    public let options: AVAudioSession.InterruptionOptions

    public init(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {
        self.type = type
        self.options = options
    }

    public static func makeMessage(_ notification: sending Notification) -> Self? {
        guard let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return nil
        }
        let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        return Self(
            type: type,
            options: AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
        )
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: AVAudioSession?) -> Notification {
        Notification(name: name, object: object, userInfo: [
            AVAudioSessionInterruptionTypeKey: message.type.rawValue,
            AVAudioSessionInterruptionOptionKey: message.options.rawValue,
        ])
    }
}

/// Message for `AVAudioSession.routeChangeNotification`.
public struct RouteChangeMessage: MainActorNotificationMessage {
    public typealias Subject = AVAudioSession

    public static var name: Notification.Name { AVAudioSession.routeChangeNotification }

    public let reason: AVAudioSession.RouteChangeReason

    public init(reason: AVAudioSession.RouteChangeReason) {
        self.reason = reason
    }

    public static func makeMessage(_ notification: sending Notification) -> Self? {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else {
            return nil
        }
        return Self(reason: reason)
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: AVAudioSession?) -> Notification {
        Notification(name: name, object: object, userInfo: [
            AVAudioSessionRouteChangeReasonKey: message.reason.rawValue,
        ])
    }
}
#endif
