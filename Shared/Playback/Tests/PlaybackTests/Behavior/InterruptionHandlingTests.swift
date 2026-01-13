//
//  InterruptionHandlingTests.swift
//  PlaybackTests
//
//  Audio session interruption tests for all PlaybackController implementations (iOS).
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
}
#endif
