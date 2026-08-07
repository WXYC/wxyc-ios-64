//
//  InterruptionHandlingTests.swift
//  Playback
//
//  Audio session interruption tests for all PlaybackController implementations (iOS).
//
//  Created by Jake Bromberg on 12/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule

// MARK: - Interruption Handling Tests (iOS)

#if os(iOS)
@Suite("Interruption Handling Tests")
@MainActor
struct InterruptionHandlingTests {

    @Test("Interruption began stops playback", arguments: PlayerControllerTestCase.allCases)
    func interruptionBeganStopsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        let stopCountBefore = harness.stopCallCount
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        #expect(harness.stopCallCount > stopCountBefore,
               "Interruption began should stop playback")
    }

    /// Per Apple's guidance: controllers ALWAYS stop on interruption began,
    /// regardless of shouldResume option (shouldResume only applies to interruption ended).
    @Test("Interruption began stops playback regardless of shouldResume", arguments: PlayerControllerTestCase.allCases)
    func interruptionBeganStopsRegardlessOfShouldResume(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let stopCountBefore = harness.stopCallCount
        // Controller should stop even with shouldResume: true
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.stopCallCount > stopCountBefore,
               "Controller should stop on interruption began regardless of shouldResume")
    }

    /// When interruption ends with shouldResume, controller should resume playback.
    @Test("Interruption ended with shouldResume resumes playback", arguments: PlayerControllerTestCase.allCases)
    func interruptionEndedWithShouldResumeResumesPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Simulate interruption began (sets wasPlayingBeforeInterruption = true and stops)
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        let playCountBefore = harness.playCallCount

        // Post interruption ended with shouldResume - should resume
        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.playCallCount > playCountBefore,
               "Interruption ended with shouldResume should resume playback")
    }

    // MARK: - RadioPlayerController-only extras (#756)

    /// RadioPlayerController, unlike AudioPlayerController, tracks interruption
    /// as a controller-level `.interrupted` state (`PlayerState` itself has no
    /// such case — see `PlayerState.swift`) so a view can distinguish "stopped
    /// because of an interruption" from an ordinary idle stop. This must be
    /// set on every `.began`, whether or not playback was actually active.
    @Test("RadioPlayerController enters .interrupted state on interruption began, whether or not playback was active")
    func radioPlayerControllerEntersInterruptedState() async {
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)
        #expect(!harness.controller.isPlaying)

        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        #expect(harness.controller.state == .interrupted,
               "RadioPlayerController should enter .interrupted even when nothing was playing")
    }

    /// RadioPlayerController captures a dedicated `InterruptionEvent` in
    /// addition to the shared `PlaybackStoppedEvent` — AudioPlayerController
    /// does not. This is a genuine per-controller extra (#756), not
    /// duplicated shared behavior.
    @Test("RadioPlayerController captures InterruptionEvent when interruption begins while playing")
    func radioPlayerControllerCapturesInterruptionEvent() async {
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        let interruptionEvents = harness.mockAnalytics.events.compactMap { $0 as? InterruptionEvent }
        #expect(interruptionEvents.count == 1)
        #expect(interruptionEvents.first?.type == .began)
    }

    /// AudioPlayerController has no equivalent `InterruptionEvent` capture —
    /// pins the negative side of the same #756 contract.
    @Test("AudioPlayerController does not capture InterruptionEvent on interruption began")
    func audioPlayerControllerDoesNotCaptureInterruptionEvent() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        let interruptionEvents = harness.mockAnalytics.events.compactMap { $0 as? InterruptionEvent }
        #expect(interruptionEvents.isEmpty)
    }
}
#endif
