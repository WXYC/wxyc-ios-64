//
//  RadioPlayerMessages.swift
//  Playback
//
//  MainActorNotificationMessage types for RadioPlayer's notification handling.
//  These enable synchronous, type-safe notification handling on the main actor.
//
//  Created by Jake Bromberg on 01/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import Core

// MARK: - Rate Change Message

/// Message for AVPlayer rate changes, indicating playback state transitions.
public struct PlayerRateDidChangeMessage: MainActorNotificationMessage {
    public typealias Subject = AVPlayer

    public static var name: Notification.Name {
        AVPlayer.rateDidChangeNotification
    }

    /// The new playback rate (> 0 means playing)
    public let rate: Float

    public static func makeMessage(_ notification: sending Notification) -> Self? {
        // Extract rate from the player object if available
        if let player = notification.object as? AVPlayer {
            return Self(rate: player.rate)
        }
        // For mock players in tests, check userInfo
        if let rate = notification.userInfo?["rate"] as? Float {
            return Self(rate: rate)
        }
        // Default to 0 if we can't determine rate
        return Self(rate: 0)
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: AVPlayer?) -> Notification {
        Notification(
            name: name,
            object: object,
            userInfo: ["rate": message.rate]
        )
    }
}

// MARK: - Playback Stalled Message

/// Message for AVPlayerItem playback stalls.
public struct PlaybackStalledMessage: MainActorNotificationMessage {
    public typealias Subject = AVPlayerItem

    public static var name: Notification.Name {
        .AVPlayerItemPlaybackStalled
    }

    public static func makeMessage(_ notification: sending Notification) -> Self? {
        Self()
    }

    @MainActor
    public static func makeNotification(_ message: Self, object: AVPlayerItem?) -> Notification {
        Notification(name: name, object: object)
    }
}
