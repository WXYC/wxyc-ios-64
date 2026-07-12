//
//  StreamStartupError.swift
//  Playback
//
//  Error surfaced when a player connects but never reaches the playing state
//  within its startup deadline.
//
//  Created by Jake Bromberg on 07/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Raised when a player successfully connects but fails to begin playback within
/// its startup deadline — i.e. it starved mid-buffering and would otherwise hang
/// in a perpetual loading state (see Sentry IOS-31, "Playback not starting").
///
/// Lives in `PlaybackCore` rather than a specific player module so it can be both
/// produced by a player (e.g. `MP3Streamer`) and classified by
/// `AudioPlayerController` on every platform, including watchOS where the
/// concrete streamer modules are not imported.
public enum StreamStartupError: Error, Equatable {
    /// Playback did not reach `.playing` within `seconds` of the play attempt.
    case timedOut(seconds: TimeInterval)
}

extension StreamStartupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Playback did not start within \(seconds)s"
        }
    }
}
