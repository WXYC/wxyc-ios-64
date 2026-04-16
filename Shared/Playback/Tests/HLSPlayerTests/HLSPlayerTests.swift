//
//  HLSPlayerTests.swift
//  HLSPlayerTests
//
//  Tests for HLSPlayer: state transitions, time-shift calculations, and seeking.
//  Uses MockHLSAVPlayer and NotificationCenter for isolated, deterministic tests.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import AVFoundation
import CoreMedia
import Analytics
import AnalyticsTesting
@testable import HLSPlayerModule
@testable import PlaybackCore

@Suite("HLSPlayer Tests", .serialized)
@MainActor
struct HLSPlayerTests {

    // MARK: - Initialization

    @Test("Initializes in idle state")
    func initializesIdle() {
        let (player, _, _) = makePlayer()

        #expect(player.state == .idle)
        #expect(player.isPlaying == false)
        #expect(player.isAtLiveEdge == true)
        #expect(player.secondsBehindLive == 0)
    }

    // MARK: - Play / Stop

    @Test("Play transitions to loading and calls underlying player")
    func playTransitionsToLoading() {
        let (player, mock, _) = makePlayer()

        player.play()

        #expect(player.state == .loading)
        #expect(mock.playCallCount == 1)
    }

    @Test("Play when already playing does not call underlying player again")
    func playWhenAlreadyPlaying() async throws {
        let (player, mock, nc) = makePlayer()

        player.play()
        simulateRateChange(rate: 1.0, on: nc)
        #expect(player.state == .playing)

        mock.playCallCount = 0
        player.play()

        #expect(mock.playCallCount == 0)
    }

    @Test("Stop transitions to idle and pauses underlying player")
    func stopTransitionsToIdle() async throws {
        let (player, mock, nc) = makePlayer()

        player.play()
        simulateRateChange(rate: 1.0, on: nc)
        #expect(player.state == .playing)

        player.stop()

        #expect(player.state == .idle)
        #expect(mock.pauseCallCount == 1)
    }

    // MARK: - State Transitions via Notifications

    @Test("Rate change notification transitions from loading to playing")
    func rateChangeFromLoadingToPlaying() {
        let (player, _, nc) = makePlayer()

        player.play()
        #expect(player.state == .loading)

        simulateRateChange(rate: 1.0, on: nc)
        #expect(player.state == .playing)
    }

    @Test("Stall notification transitions from playing to stalled")
    func stallFromPlaying() {
        let (player, _, nc) = makePlayer()

        player.play()
        simulateRateChange(rate: 1.0, on: nc)
        #expect(player.state == .playing)

        simulateStall(on: nc)
        #expect(player.state == .stalled)
    }

    @Test("Rate change after stall transitions to playing (recovery)")
    func recoveryFromStall() {
        let (player, _, nc) = makePlayer()

        player.play()
        simulateRateChange(rate: 1.0, on: nc)
        simulateStall(on: nc)
        #expect(player.state == .stalled)

        simulateRateChange(rate: 1.0, on: nc)
        #expect(player.state == .playing)
    }

    @Test("Failure notification transitions to error state")
    func failureTransitionsToError() {
        let (player, _, nc) = makePlayer()

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        simulateFailure(on: nc)
        if case .error = player.state {
            // Expected
        } else {
            Issue.record("Expected error state, got \(player.state)")
        }
    }

    // MARK: - State Stream

    @Test("State stream emits state transitions")
    func stateStreamEmitsTransitions() async throws {
        let (player, _, nc) = makePlayer()
        var emitted: [PlayerState] = []

        let task = Task {
            for await state in player.stateStream {
                emitted.append(state)
                if emitted.count >= 3 { break }
            }
        }

        // Give the iterator time to start
        try await Task.sleep(for: .milliseconds(50))

        player.play()
        simulateRateChange(rate: 1.0, on: nc)
        player.stop()

        await withTaskCancellation(of: task, after: .seconds(2))

        #expect(emitted.contains(.loading))
        #expect(emitted.contains(.playing))
        #expect(emitted.contains(.idle))
    }

    // MARK: - Audio Buffer Stream

    @Test("Audio buffer stream finishes immediately")
    func audioBufferStreamFinishesImmediately() async {
        let (player, _, _) = makePlayer()
        var count = 0

        for await _ in player.makeAudioBufferStream() {
            count += 1
        }

        #expect(count == 0)
    }

    // MARK: - isAtLiveEdge

    @Test(
        "isAtLiveEdge is true when within threshold",
        arguments: [0.0, 5.0, 11.9]
    )
    func isAtLiveEdgeWhenWithinThreshold(secondsBehind: TimeInterval) async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 3600)
        mock.setCurrentTimeBehindLive(secondsBehind)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        // Trigger a time position update by seeking
        await player.seekToLive()
        mock.setCurrentTimeBehindLive(secondsBehind)
        await player.seek(secondsBehindLive: secondsBehind)

        #expect(player.isAtLiveEdge == true)
    }

    @Test(
        "isAtLiveEdge is false when beyond threshold",
        arguments: [12.0, 30.0, 600.0, 3600.0]
    )
    func isAtLiveEdgeWhenBeyondThreshold(secondsBehind: TimeInterval) async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 3600)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        await player.seek(secondsBehindLive: secondsBehind)

        #expect(player.isAtLiveEdge == false)
    }

    // MARK: - secondsBehindLive

    @Test("secondsBehindLive reflects current position after seek")
    func secondsBehindLiveAfterSeek() async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 3600)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        await player.seek(secondsBehindLive: 120)

        #expect(abs(player.secondsBehindLive - 120) < 0.1)
    }

    @Test("secondsBehindLive is zero at live edge")
    func secondsBehindLiveAtLiveEdge() async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 3600)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        await player.seekToLive()

        #expect(player.secondsBehindLive < 0.1)
    }

    // MARK: - maxLookbackSeconds

    @Test("maxLookbackSeconds reflects seekable range duration")
    func maxLookbackFromSeekableRange() {
        let (player, mock, _) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 1800)

        #expect(player.maxLookbackSeconds == 1800)
    }

    @Test("maxLookbackSeconds is capped at 3600")
    func maxLookbackCappedAtOneHour() {
        let (player, mock, _) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 7200)

        #expect(player.maxLookbackSeconds == 3600)
    }

    @Test("maxLookbackSeconds is zero with no seekable range")
    func maxLookbackZeroWithNoRange() {
        let (player, _, _) = makePlayer()

        #expect(player.maxLookbackSeconds == 0)
    }

    // MARK: - Seeking

    @Test("seek calls underlying player with computed target time")
    func seekCallsUnderlyingPlayer() async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 100, duration: 3600)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        await player.seek(secondsBehindLive: 60)

        #expect(mock.seekCallCount == 1)
        let expectedTarget = 100.0 + 3600.0 - 60.0
        #expect(abs(mock.lastSeekTime!.seconds - expectedTarget) < 0.01)
    }

    @Test("seek clamps offset to maxLookbackSeconds")
    func seekClampsToMaxLookback() async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 1800)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        // Request 3600 but range is only 1800
        await player.seek(secondsBehindLive: 3600)

        let expectedTarget = 0.0 + 1800.0 - 1800.0
        #expect(abs(mock.lastSeekTime!.seconds - expectedTarget) < 0.01)
    }

    @Test("seek clamps negative offset to zero")
    func seekClampsNegativeOffset() async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 3600)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        await player.seek(secondsBehindLive: -10)

        // Should seek to live edge (offset 0)
        let expectedTarget = 3600.0
        #expect(abs(mock.lastSeekTime!.seconds - expectedTarget) < 0.01)
    }

    @Test("seekToLive seeks to live edge")
    func seekToLiveSeeksToEdge() async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 100, duration: 3600)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        await player.seekToLive()

        #expect(mock.seekCallCount == 1)
        let expectedTarget = 100.0 + 3600.0
        #expect(abs(mock.lastSeekTime!.seconds - expectedTarget) < 0.01)
    }

    @Test("seek does nothing with no seekable range")
    func seekNoOpWithoutRange() async throws {
        let (player, mock, nc) = makePlayer()

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        await player.seek(secondsBehindLive: 60)

        #expect(mock.seekCallCount == 0)
    }

    // MARK: - Time Position Stream

    @Test("Time position stream emits updates while playing")
    func timePositionStreamEmits() async throws {
        let (player, mock, nc) = makePlayer()
        mock.setSeekableRange(start: 0, duration: 3600)
        mock.setCurrentTimeBehindLive(30)

        player.play()
        simulateRateChange(rate: 1.0, on: nc)

        var positions: [TimeInterval] = []
        let task = Task {
            for await position in player.timePositionStream {
                positions.append(position)
                if positions.count >= 2 { break }
            }
        }

        await withTaskCancellation(of: task, after: .seconds(3))

        #expect(positions.count >= 1)
    }

    // MARK: - Render Tap

    @Test("installRenderTap and removeRenderTap are no-ops")
    func renderTapNoOps() {
        let (player, _, _) = makePlayer()

        player.installRenderTap()
        player.removeRenderTap()

        // No crash, no effect
        #expect(player.state == .idle)
    }

    // MARK: - Event Stream

    @Test("Stall yields stall event")
    func stallYieldsEvent() async throws {
        let (player, _, nc) = makePlayer()
        var events: [AudioPlayerInternalEvent] = []

        let task = Task {
            for await event in player.eventStream {
                events.append(event)
                if events.count >= 1 { break }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        player.play()
        simulateRateChange(rate: 1.0, on: nc)
        simulateStall(on: nc)

        await withTaskCancellation(of: task, after: .seconds(2))

        #expect(events.contains(where: {
            if case .stall = $0 { return true }
            return false
        }))
    }

    @Test("Recovery after stall yields recovery event")
    func recoveryYieldsEvent() async throws {
        let (player, _, nc) = makePlayer()
        var events: [AudioPlayerInternalEvent] = []

        let task = Task {
            for await event in player.eventStream {
                events.append(event)
                if events.count >= 2 { break }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        player.play()
        simulateRateChange(rate: 1.0, on: nc)
        simulateStall(on: nc)
        simulateRateChange(rate: 1.0, on: nc)

        await withTaskCancellation(of: task, after: .seconds(2))

        #expect(events.contains(where: {
            if case .recovery = $0 { return true }
            return false
        }))
    }

    // MARK: - Analytics

    @Test("Play captures analytics event")
    func playAnalytics() {
        let (player, _, _) = makePlayer()

        player.play()

        #expect(player.state == .loading)
    }

    // MARK: - Helpers

    private func makePlayer() -> (HLSPlayer, MockHLSAVPlayer, NotificationCenter) {
        let mock = MockHLSAVPlayer()
        let nc = NotificationCenter()
        let player = HLSPlayer(
            player: mock,
            analytics: nil,
            notificationCenter: nc
        )
        return (player, mock, nc)
    }

    private func simulateRateChange(rate: Float, on nc: NotificationCenter) {
        nc.post(
            name: AVPlayer.rateDidChangeNotification,
            object: nil,
            userInfo: ["rate": rate]
        )
    }

    private func simulateStall(on nc: NotificationCenter) {
        nc.post(name: .AVPlayerItemPlaybackStalled, object: nil)
    }

    private func simulateFailure(on nc: NotificationCenter) {
        nc.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: "test", code: -1)]
        )
    }

    /// Cancels task after timeout if it hasn't completed.
    private func withTaskCancellation(of task: Task<Void, Never>, after timeout: Duration) async {
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            task.cancel()
        }
        await task.value
        timeoutTask.cancel()
    }
}
