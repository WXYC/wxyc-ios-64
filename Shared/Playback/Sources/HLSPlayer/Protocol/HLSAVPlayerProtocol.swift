//
//  HLSAVPlayerProtocol.swift
//  HLSPlayerModule
//
//  Abstraction over AVPlayer for HLS playback, enabling dependency injection and testability.
//  The real implementation wraps AVPlayer; tests use MockHLSAVPlayer.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AVFoundation
import CoreMedia

/// Abstraction over AVPlayer for HLS playback operations.
///
/// Provides the subset of AVPlayer + AVPlayerItem functionality needed by `HLSPlayer`:
/// time queries, seekable range access, and seeking. State changes are observed via
/// `NotificationCenter` (same pattern as `RadioPlayer`).
@MainActor
public protocol HLSAVPlayerProtocol: Sendable {
    var rate: Float { get }
    func play()
    func pause()
    func currentTime() -> CMTime
    var seekableTimeRanges: [NSValue] { get }
    func seek(to time: CMTime) async -> Bool

    /// The real `AVPlayer` this instance is backed by, or `nil` if it isn't
    /// backed by one (e.g. a test double). `HLSPlayer` passes this as the
    /// subject when registering its rate-change observer, scoping the
    /// observer to this specific player instance so it doesn't fire for
    /// rate changes on some other `AVPlayer` sharing the same
    /// `NotificationCenter`.
    var underlyingAVPlayer: AVPlayer? { get }
}

// MARK: - AVPlayer Adapter

/// Wraps a real `AVPlayer` to conform to `HLSAVPlayerProtocol`.
///
/// Bridges `seekableTimeRanges` and `seek(to:)` through the player's current item.
@MainActor
final class AVPlayerHLSAdapter: HLSAVPlayerProtocol, @unchecked Sendable {
    private let player: AVPlayer

    init(url: URL) {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetAllowsConstrainedNetworkAccessKey: true,
            AVURLAssetAllowsExpensiveNetworkAccessKey: true,
        ])
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    var rate: Float { player.rate }

    var underlyingAVPlayer: AVPlayer? { player }

    func play() { player.play() }

    func pause() { player.pause() }

    func currentTime() -> CMTime { player.currentTime() }

    var seekableTimeRanges: [NSValue] {
        player.currentItem?.seekableTimeRanges ?? []
    }

    func seek(to time: CMTime) async -> Bool {
        await withCheckedContinuation { continuation in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                continuation.resume(returning: finished)
            }
        }
    }
}
