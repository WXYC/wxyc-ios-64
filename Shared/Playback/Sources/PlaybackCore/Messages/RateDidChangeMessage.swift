//
//  RateDidChangeMessage.swift
//  PlaybackCore
//
//  Typed MainActorNotificationMessage wrapper around AVPlayer.rateDidChangeNotification,
//  shared by RadioPlayerModule and HLSPlayerModule. It replaces the byte-identical
//  PlayerRateDidChangeMessage and HLSRateDidChangeMessage (#324).
//
//  Collapsing those two into one is behavior-preserving because the Swift type was never
//  a delivery discriminator: both declared `name` as AVPlayer.rateDidChangeNotification,
//  and addMainActorObserver(of:for:using:) registers on that Notification.Name alone. The
//  only discriminator is, and was, the subject passed to `of:` — non-nil scopes delivery
//  to one AVPlayer, nil receives every rate change on the center. Both players observe
//  scoped: RadioPlayer passes a real AVPlayer (AVPlayer conforms to PlayerProtocol
//  directly), and HLSPlayer passes `player.underlyingAVPlayer` (PR #878 — its production
//  AVPlayerHLSAdapter wraps an AVPlayer rather than subclassing one, so the earlier
//  `player as? AVPlayer` cast was always nil there and silently observed unscoped).
//  See RateDidChangeMessageTests for the executable form of that scoping contract.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AVFoundation
import Core
import Foundation

/// Message for `AVPlayer.rateDidChangeNotification`, indicating playback state transitions.
public struct RateDidChangeMessage: MainActorNotificationMessage {
    public typealias Subject = AVPlayer

    public static var name: Notification.Name {
        AVPlayer.rateDidChangeNotification
    }

    /// The new playback rate (> 0 means playing).
    public let rate: Float

    public init(rate: Float) {
        self.rate = rate
    }

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
