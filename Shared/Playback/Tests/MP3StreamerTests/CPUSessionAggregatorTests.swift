//
//  CPUSessionAggregatorTests.swift
//  MP3StreamerTests
//
//  Tests for the CPUSessionAggregator.
//

import Testing
import Foundation
@testable import MP3StreamerModule
@testable import PlaybackCore

#if !os(watchOS)

@Suite("CPUSessionAggregator")
@MainActor
struct CPUSessionAggregatorTests {

    // MARK: - Basic Session Tests

    @Test("Flush does nothing without samples")
    func flushWithoutSamples() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.isEmpty)
    }

    @Test("Records samples and calculates average")
    func calculatesAverage() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(10.0)
        aggregator._testInjectSample(20.0)
        aggregator._testInjectSample(30.0)
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 1)
        let event = analytics.cpuSessionEvents[0]
        #expect(event.averageCPU == 20.0) // (10 + 20 + 30) / 3
        #expect(event.sampleCount == 3)
    }

    @Test("Tracks maximum CPU")
    func tracksMaximum() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(15.0)
        aggregator._testInjectSample(85.0)
        aggregator._testInjectSample(25.0)
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 1)
        let event = analytics.cpuSessionEvents[0]
        #expect(event.maxCPU == 85.0)
    }

    @Test("Reports correct end reason")
    func reportsCorrectEndReason() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator.endSession(reason: .interrupted)

        #expect(analytics.cpuSessionEvents.count == 1)
        #expect(analytics.cpuSessionEvents[0].endReason == .interrupted)
    }

    @Test("Reports correct player type")
    func reportsCorrectPlayerType() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .radioPlayer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 1)
        #expect(analytics.cpuSessionEvents[0].playerType == .radioPlayer)
    }

    // MARK: - Context Tests

    @Test("Reports foreground context")
    func reportsForegroundContext() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 1)
        #expect(analytics.cpuSessionEvents[0].context == .foreground)
    }

    @Test("Reports background context")
    func reportsBackgroundContext() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .background)
        aggregator._testInjectSample(50.0)
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 1)
        #expect(analytics.cpuSessionEvents[0].context == .background)
    }

    // MARK: - Context Transition Tests

    @Test("Context transition ends current session with backgrounded reason")
    func contextTransitionEndsWithBackgroundedReason() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator.transitionContext(to: .background)

        #expect(analytics.cpuSessionEvents.count == 1)
        let event = analytics.cpuSessionEvents[0]
        #expect(event.context == .foreground)
        #expect(event.endReason == .backgrounded)
    }

    @Test("Context transition ends current session with foregrounded reason")
    func contextTransitionEndsWithForegroundedReason() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .background)
        aggregator._testInjectSample(50.0)
        aggregator.transitionContext(to: .foreground)

        #expect(analytics.cpuSessionEvents.count == 1)
        let event = analytics.cpuSessionEvents[0]
        #expect(event.context == .background)
        #expect(event.endReason == .foregrounded)
    }

    @Test("Context transition starts new session")
    func contextTransitionStartsNewSession() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator.transitionContext(to: .background)

        // Session should still be active after transition
        #expect(aggregator.isSessionActive)
    }

    @Test("Multiple transitions create multiple events")
    func multipleTransitionsCreateMultipleEvents() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        // Start foreground session
        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(30.0)

        // Transition to background
        aggregator.transitionContext(to: .background)
        aggregator._testInjectSample(20.0)

        // Transition back to foreground
        aggregator.transitionContext(to: .foreground)
        aggregator._testInjectSample(40.0)

        // End final session
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 3)

        // First event: foreground -> backgrounded
        #expect(analytics.cpuSessionEvents[0].context == .foreground)
        #expect(analytics.cpuSessionEvents[0].endReason == .backgrounded)
        #expect(analytics.cpuSessionEvents[0].averageCPU == 30.0)

        // Second event: background -> foregrounded
        #expect(analytics.cpuSessionEvents[1].context == .background)
        #expect(analytics.cpuSessionEvents[1].endReason == .foregrounded)
        #expect(analytics.cpuSessionEvents[1].averageCPU == 20.0)

        // Third event: foreground -> user stopped
        #expect(analytics.cpuSessionEvents[2].context == .foreground)
        #expect(analytics.cpuSessionEvents[2].endReason == .userStopped)
        #expect(analytics.cpuSessionEvents[2].averageCPU == 40.0)
    }

    // MARK: - Edge Cases

    @Test("Ignores invalid CPU readings")
    func ignoresInvalidReadings() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator._testInjectSample(-1.0) // Invalid
        aggregator._testInjectSample(60.0)
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 1)
        let event = analytics.cpuSessionEvents[0]
        #expect(event.sampleCount == 2) // Only valid samples counted
        #expect(event.averageCPU == 55.0) // (50 + 60) / 2
    }

    @Test("Same context transition does nothing")
    func sameContextTransitionDoesNothing() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator.transitionContext(to: .foreground) // Same context

        // No event should be emitted yet
        #expect(analytics.cpuSessionEvents.isEmpty)
        #expect(aggregator.isSessionActive)
    }

    @Test("Transition when not active does nothing")
    func transitionWhenNotActiveDoesNothing() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        // Try to transition without starting a session
        aggregator.transitionContext(to: .background)

        #expect(analytics.cpuSessionEvents.isEmpty)
        #expect(!aggregator.isSessionActive)
    }

    @Test("End session when not active does nothing")
    func endSessionWhenNotActiveDoesNothing() {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        // Try to end without starting
        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.isEmpty)
    }

    @Test("Duration is calculated correctly")
    func durationIsCalculatedCorrectly() async throws {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)

        // Wait a small amount of time
        try await Task.sleep(for: .milliseconds(100))

        aggregator.endSession(reason: .userStopped)

        #expect(analytics.cpuSessionEvents.count == 1)
        #expect(analytics.cpuSessionEvents[0].durationSeconds >= 0.1)
    }

    // MARK: - All End Reasons

    @Test("Reports all end reason types", arguments: [
        CPUSessionEndReason.userStopped,
        CPUSessionEndReason.backgrounded,
        CPUSessionEndReason.foregrounded,
        CPUSessionEndReason.interrupted,
        CPUSessionEndReason.stalled,
        CPUSessionEndReason.routeDisconnected,
        CPUSessionEndReason.error
    ])
    func reportsAllEndReasonTypes(reason: CPUSessionEndReason) {
        let analytics = MockPlaybackAnalytics()
        let aggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { .avAudioStreamer }
        )

        aggregator._testStartSessionWithoutMonitor(context: .foreground)
        aggregator._testInjectSample(50.0)
        aggregator.endSession(reason: reason)

        #expect(analytics.cpuSessionEvents.count == 1)
        #expect(analytics.cpuSessionEvents[0].endReason == reason)
    }
}

#endif // !os(watchOS)
