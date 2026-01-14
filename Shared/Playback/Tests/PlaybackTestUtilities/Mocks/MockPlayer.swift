//
//  MockPlayer.swift
//  Playback
//
//  Mock implementation of PlayerProtocol (AVPlayer abstraction) for testing RadioPlayer.
//
//  Created by Jake Bromberg on 01/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
@testable import PlaybackCore

/// Mock for PlayerProtocol (AVPlayer abstraction) used for testing RadioPlayer.
///
/// Uses @MainActor isolation with @preconcurrency protocol conformance for thread safety.
/// All test suites using this mock are @MainActor-isolated, so this pattern is appropriate.
@MainActor
public final class MockPlayer: @preconcurrency PlayerProtocol {
    public var rate: Float = 0
    public var playCallCount = 0
    public var pauseCallCount = 0
    public var replaceCurrentItemCallCount = 0
    public var lastReplacedItem: AVPlayerItem?

    /// If true, play() automatically sets rate to 1.0
    public var autoSetRateOnPlay: Bool

    public init(autoSetRateOnPlay: Bool = true) {
        self.autoSetRateOnPlay = autoSetRateOnPlay
    }

    public func play() {
        playCallCount += 1
        if autoSetRateOnPlay {
            rate = 1.0
        }
    }

    public func pause() {
        pauseCallCount += 1
        rate = 0
    }

    public func replaceCurrentItem(with item: AVPlayerItem?) {
        replaceCurrentItemCallCount += 1
        lastReplacedItem = item
        rate = 0
    }

    public func reset() {
        rate = 0
        playCallCount = 0
        pauseCallCount = 0
        replaceCurrentItemCallCount = 0
        lastReplacedItem = nil
    }
}
