//
//  TimeShiftablePlayer.swift
//  PlaybackCore
//
//  Protocol for audio players that support time-shifting (seeking within a live stream).
//  Extends AudioPlayerProtocol to add seek and time position capabilities.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A player that supports time-shifting within a live stream.
///
/// Extends `AudioPlayerProtocol` with seeking capabilities, allowing listeners
/// to scrub backwards from the live edge. Players that don't support time-shifting
/// (like `RadioPlayer` and `MP3Streamer`) are unaffected -- controllers use
/// `as? TimeShiftablePlayer` for optional capability discovery.
@MainActor
public protocol TimeShiftablePlayer: AudioPlayerProtocol {
    /// Whether the player is currently at or near the live edge.
    ///
    /// Returns `true` when the current playback position is within 12 seconds
    /// (approximately 2 HLS segments) of the live edge.
    var isAtLiveEdge: Bool { get }

    /// The number of seconds the current playback position is behind the live edge.
    var secondsBehindLive: TimeInterval { get }

    /// The maximum number of seconds the player can seek backwards from the live edge.
    ///
    /// Derived from the HLS playlist's seekable time range, capped at 3600 seconds (1 hour).
    var maxLookbackSeconds: TimeInterval { get }

    /// A stream of periodic time position updates (every 0.5 seconds).
    ///
    /// Yields the current `secondsBehindLive` value at each interval.
    var timePositionStream: AsyncStream<TimeInterval> { get }

    /// Seek to a position relative to the live edge.
    ///
    /// - Parameter secondsBehindLive: The desired offset in seconds behind the live edge.
    ///   A value of 0 seeks to the live edge. Values are clamped to `maxLookbackSeconds`.
    func seek(secondsBehindLive: TimeInterval) async

    /// Seek to the live edge of the stream.
    func seekToLive() async
}
