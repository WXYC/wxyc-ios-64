//
//  MockHLSAVPlayer.swift
//  HLSPlayerTests
//
//  Mock implementation of HLSAVPlayerProtocol for testing HLSPlayer.
//  Provides controllable seekable time ranges, current time, and seek behavior.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia
@testable import HLSPlayerModule

@MainActor
final class MockHLSAVPlayer: HLSAVPlayerProtocol {
    var rate: Float = 0
    var playCallCount = 0
    var pauseCallCount = 0
    var seekCallCount = 0
    var lastSeekTime: CMTime?
    var seekResult = true
    var autoSetRateOnPlay = true

    var mockCurrentTime: CMTime = .zero
    var mockSeekableTimeRanges: [NSValue] = []

    func play() {
        playCallCount += 1
        if autoSetRateOnPlay {
            rate = 1.0
        }
    }

    func pause() {
        pauseCallCount += 1
        rate = 0
    }

    func currentTime() -> CMTime {
        mockCurrentTime
    }

    var seekableTimeRanges: [NSValue] {
        mockSeekableTimeRanges
    }

    func seek(to time: CMTime) async -> Bool {
        seekCallCount += 1
        lastSeekTime = time
        if seekResult {
            mockCurrentTime = time
        }
        return seekResult
    }

    func reset() {
        rate = 0
        playCallCount = 0
        pauseCallCount = 0
        seekCallCount = 0
        lastSeekTime = nil
        seekResult = true
        mockCurrentTime = .zero
        mockSeekableTimeRanges = []
    }

    // MARK: - Helpers

    /// Sets up a seekable range simulating a live HLS stream.
    ///
    /// - Parameters:
    ///   - start: The start time in seconds.
    ///   - duration: The duration of the seekable range in seconds.
    func setSeekableRange(start: TimeInterval, duration: TimeInterval) {
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        mockSeekableTimeRanges = [NSValue(timeRange: range)]
    }

    /// Sets the current time to be a given number of seconds behind the live edge.
    func setCurrentTimeBehindLive(_ secondsBehind: TimeInterval) {
        guard let range = mockSeekableTimeRanges.first?.timeRangeValue else { return }
        let liveEdge = range.start + range.duration
        mockCurrentTime = CMTime(
            seconds: liveEdge.seconds - secondsBehind,
            preferredTimescale: 600
        )
    }
}
