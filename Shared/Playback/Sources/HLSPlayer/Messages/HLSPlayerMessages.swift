//
//  HLSPlayerMessages.swift
//  HLSPlayerModule
//
//  MainActorNotificationMessage types for HLSPlayer's notification handling.
//  Mirrors the message types in RadioPlayerModule for the same AVPlayer notifications.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import Core

// MARK: - Rate Change Message

/// Message for AVPlayer rate changes, indicating playback state transitions.
struct HLSRateDidChangeMessage: MainActorNotificationMessage {
    typealias Subject = AVPlayer

    static var name: Notification.Name {
        AVPlayer.rateDidChangeNotification
    }

    let rate: Float

    static func makeMessage(_ notification: sending Notification) -> Self? {
        if let player = notification.object as? AVPlayer {
            return Self(rate: player.rate)
        }
        if let rate = notification.userInfo?["rate"] as? Float {
            return Self(rate: rate)
        }
        return Self(rate: 0)
    }

    @MainActor
    static func makeNotification(_ message: Self, object: AVPlayer?) -> Notification {
        Notification(
            name: name,
            object: object,
            userInfo: ["rate": message.rate]
        )
    }
}

// MARK: - Playback Stalled Message

/// Message for AVPlayerItem playback stalls.
struct HLSPlaybackStalledMessage: MainActorNotificationMessage {
    typealias Subject = AVPlayerItem

    static var name: Notification.Name {
        .AVPlayerItemPlaybackStalled
    }

    static func makeMessage(_ notification: sending Notification) -> Self? {
        Self()
    }

    @MainActor
    static func makeNotification(_ message: Self, object: AVPlayerItem?) -> Notification {
        Notification(name: name, object: object)
    }
}

// MARK: - Failed to Play to End Message

/// Message for AVPlayerItem failure to play to end.
struct HLSFailedToPlayToEndMessage: MainActorNotificationMessage {
    typealias Subject = AVPlayerItem

    static var name: Notification.Name {
        .AVPlayerItemFailedToPlayToEndTime
    }

    let error: (any Error)?

    static func makeMessage(_ notification: sending Notification) -> Self? {
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? any Error
        return Self(error: error)
    }

    @MainActor
    static func makeNotification(_ message: Self, object: AVPlayerItem?) -> Notification {
        var userInfo: [String: Any]?
        if let error = message.error {
            userInfo = [AVPlayerItemFailedToPlayToEndTimeErrorKey: error]
        }
        return Notification(name: name, object: object, userInfo: userInfo)
    }
}
