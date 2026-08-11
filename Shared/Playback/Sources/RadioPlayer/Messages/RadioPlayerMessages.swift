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

// MARK: - Playback Stalled Message

/// Message for AVPlayerItem playback stalls.
struct PlaybackStalledMessage: MainActorNotificationMessage {
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
