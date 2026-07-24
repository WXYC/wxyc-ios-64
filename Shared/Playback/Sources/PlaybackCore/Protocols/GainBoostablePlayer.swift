//
//  GainBoostablePlayer.swift
//  PlaybackCore
//
//  Protocol for audio players that support an output gain boost, in decibels.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A player that can boost (or cut) its output level, expressed in decibels.
///
/// The live WXYC stream is mastered a few dB below full scale, leaving headroom.
/// A gain-boostable player can raise the output toward 0 dBFS to make the stream
/// louder. Players that can't boost — the AVPlayer-based `RadioPlayer` and
/// `HLSPlayer` — simply don't conform; controllers use `as? GainBoostablePlayer`
/// for optional capability discovery, mirroring `TimeShiftablePlayer`.
@MainActor
public protocol GainBoostablePlayer: AudioPlayerProtocol {
    /// Output gain applied to the stream, in decibels. `0` is unity — no boost
    /// or cut. Implementations clamp to their supported range.
    var gainDecibels: Float { get set }
}
