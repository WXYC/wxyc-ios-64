//
//  PlaybackInterruptionRouteHandlerTests.swift
//  Playback
//
//  Direct unit tests for the extracted `PlaybackInterruptionRouteHandler`
//  component (#756) — the interruption/route-change notification subscription,
//  case switch, and shared `PlaybackStoppedEvent` capture shared by
//  AudioPlayerController and RadioPlayerController. These exercise the
//  component in isolation, no controller involved; `Behavior/InterruptionHandlingTests.swift`
//  and `Behavior/RouteChangeBehaviorTests.swift` cover the same behavior
//  end-to-end through both controllers.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS)
import Testing
import Foundation
import AVFoundation
import AnalyticsTesting
@testable import PlaybackCore

@Suite("PlaybackInterruptionRouteHandler Tests")
@MainActor
struct PlaybackInterruptionRouteHandlerTests {

    // MARK: - Fixture

    /// Records every hook invocation and lets a test drive `isPlaying` /
    /// `wasPlayingBeforeRouteDisconnect` as controllable state, mirroring how
    /// a real controller would wire the component.
    @MainActor
    private final class Fixture {
        let notificationCenter = NotificationCenter()
        let analytics = MockStructuredAnalytics()

        var isPlaying = false
        var sessionID: String? = "session-1"
        var playbackDuration: TimeInterval = 42
        var wasPlayingBeforeRouteDisconnect = false

        private(set) var stopCalls: [PlaybackReason] = []
        private(set) var playCalls: [PlaybackReason] = []
        private(set) var interruptionsReceived: [AVAudioSession.InterruptionType] = []
        private(set) var routeChangesReceived: [AVAudioSession.RouteChangeReason] = []
        private(set) var willStopForPlaybackCount = 0
        private(set) var interruptionBeganHandledCount = 0
        private(set) var interruptionEndedWithoutResumeCount = 0
        private(set) var routeChangeRestartFallbackCount = 0

        lazy var handler = PlaybackInterruptionRouteHandler(
            notificationCenter: notificationCenter,
            isPlaying: { [weak self] in self?.isPlaying ?? false },
            sessionID: { [weak self] in self?.sessionID },
            playbackDuration: { [weak self] in self?.playbackDuration ?? 0 },
            analytics: analytics,
            stop: { [weak self] reason in self?.stopCalls.append(reason) },
            play: { [weak self] reason in self?.playCalls.append(reason) },
            getWasPlayingBeforeRouteDisconnect: { [weak self] in self?.wasPlayingBeforeRouteDisconnect ?? false },
            setWasPlayingBeforeRouteDisconnect: { [weak self] value in self?.wasPlayingBeforeRouteDisconnect = value },
            onInterruptionReceived: { [weak self] type in self?.interruptionsReceived.append(type) },
            onInterruptionWillStopForPlayback: { [weak self] in self?.willStopForPlaybackCount += 1 },
            onInterruptionBeganHandled: { [weak self] in self?.interruptionBeganHandledCount += 1 },
            onInterruptionEndedWithoutResume: { [weak self] in self?.interruptionEndedWithoutResumeCount += 1 },
            onRouteChangeReceived: { [weak self] reason in self?.routeChangesReceived.append(reason) },
            onRouteChangeRestartFallback: { [weak self] in self?.routeChangeRestartFallbackCount += 1 }
        )

        func postInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions = []) {
            notificationCenter.post(InterruptionMessage(type: type, options: options), subject: nil as AVAudioSession?)
        }

        func postRouteChange(reason: AVAudioSession.RouteChangeReason) {
            notificationCenter.post(RouteChangeMessage(reason: reason), subject: nil as AVAudioSession?)
        }
    }

    // MARK: - Interruption began

    @Test("Interruption began while playing captures PlaybackStoppedEvent and calls stop")
    func interruptionBeganWhilePlayingStops() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.isPlaying = true

        fixture.postInterruption(type: .began)

        #expect(fixture.stopCalls == [.interruptionBegan])
        let stopped = fixture.analytics.events.compactMap { $0 as? PlaybackStoppedEvent }
        #expect(stopped.count == 1)
        #expect(stopped.first?.reason == PlaybackReason.interruptionBegan.rawValue)
        #expect(stopped.first?.duration == 42)
        #expect(stopped.first?.sessionID == "session-1")
    }

    @Test("Interruption began while not playing does not stop or capture analytics")
    func interruptionBeganWhileNotPlayingIsNoOp() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.isPlaying = false

        fixture.postInterruption(type: .began)

        #expect(fixture.stopCalls.isEmpty)
        #expect(fixture.analytics.events.isEmpty)
    }

    @Test("onInterruptionWillStopForPlayback fires before the shared PlaybackStoppedEvent capture, only while playing")
    func onWillStopFiresBeforeSharedCaptureOnlyWhilePlaying() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.isPlaying = true

        fixture.postInterruption(type: .began)
        #expect(fixture.willStopForPlaybackCount == 1)

        fixture.isPlaying = false
        fixture.postInterruption(type: .began)
        #expect(fixture.willStopForPlaybackCount == 1, "Must not fire when nothing was playing to stop")
    }

    @Test("onInterruptionBeganHandled fires unconditionally on .began, whether or not playback was active")
    func onInterruptionBeganHandledAlwaysFires() {
        let fixture = Fixture()
        _ = fixture.handler

        fixture.isPlaying = false
        fixture.postInterruption(type: .began)
        #expect(fixture.interruptionBeganHandledCount == 1)

        fixture.isPlaying = true
        fixture.postInterruption(type: .began)
        #expect(fixture.interruptionBeganHandledCount == 2)
    }

    // MARK: - Interruption ended

    @Test("Interruption ended with shouldResume, after a began-while-playing, resumes playback")
    func interruptionEndedWithShouldResumeResumes() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.isPlaying = true
        fixture.postInterruption(type: .began)

        fixture.postInterruption(type: .ended, options: .shouldResume)

        #expect(fixture.playCalls == [.resumeAfterInterruption])
        #expect(fixture.interruptionEndedWithoutResumeCount == 0)
    }

    @Test("Interruption ended without shouldResume calls the fallback hook instead of resuming")
    func interruptionEndedWithoutShouldResumeCallsFallback() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.isPlaying = true
        fixture.postInterruption(type: .began)

        fixture.postInterruption(type: .ended, options: [])

        #expect(fixture.playCalls.isEmpty)
        #expect(fixture.interruptionEndedWithoutResumeCount == 1)
    }

    @Test("Interruption ended with shouldResume but no prior began-while-playing calls the fallback hook, not resume")
    func interruptionEndedWithShouldResumeButNoPriorPlaybackCallsFallback() {
        let fixture = Fixture()
        _ = fixture.handler
        // No .began posted at all — mirrors an .ended arriving with nothing to resume.

        fixture.postInterruption(type: .ended, options: .shouldResume)

        #expect(fixture.playCalls.isEmpty)
        #expect(fixture.interruptionEndedWithoutResumeCount == 1)
    }

    @Test("wasPlayingBeforeInterruption is cleared after .ended, so a second .ended does not resume")
    func wasPlayingBeforeInterruptionClearedAfterEnded() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.isPlaying = true
        fixture.postInterruption(type: .began)
        fixture.postInterruption(type: .ended, options: .shouldResume)
        #expect(fixture.playCalls == [.resumeAfterInterruption])

        fixture.postInterruption(type: .ended, options: .shouldResume)

        #expect(fixture.playCalls == [.resumeAfterInterruption], "A second .ended with nothing new to resume must not resume again")
    }

    // MARK: - Route change: oldDeviceUnavailable

    @Test("oldDeviceUnavailable while playing captures PlaybackStoppedEvent, stops, and records wasPlayingBeforeRouteDisconnect")
    func oldDeviceUnavailableWhilePlayingStops() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.isPlaying = true

        fixture.postRouteChange(reason: .oldDeviceUnavailable)

        #expect(fixture.stopCalls == [.routeDisconnected])
        #expect(fixture.wasPlayingBeforeRouteDisconnect == true)
        let stopped = fixture.analytics.events.compactMap { $0 as? PlaybackStoppedEvent }
        #expect(stopped.count == 1)
        #expect(stopped.first?.reason == PlaybackReason.routeDisconnected.rawValue)
    }

    @Test("oldDeviceUnavailable while not playing does not stop, but still clears wasPlayingBeforeRouteDisconnect")
    func oldDeviceUnavailableWhileNotPlayingIsSafe() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.wasPlayingBeforeRouteDisconnect = true
        fixture.isPlaying = false

        fixture.postRouteChange(reason: .oldDeviceUnavailable)

        #expect(fixture.stopCalls.isEmpty)
        #expect(fixture.analytics.events.isEmpty)
        #expect(fixture.wasPlayingBeforeRouteDisconnect == false)
    }

    // MARK: - Route change: newDeviceAvailable

    @Test("newDeviceAvailable resumes when wasPlayingBeforeRouteDisconnect is set")
    func newDeviceAvailableResumesWhenFlagged() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.wasPlayingBeforeRouteDisconnect = true

        fixture.postRouteChange(reason: .newDeviceAvailable)

        #expect(fixture.playCalls == [.resumeAfterRouteReconnect])
        #expect(fixture.routeChangeRestartFallbackCount == 0)
    }

    @Test("newDeviceAvailable calls the restart-fallback hook, not resume, when the flag is unset")
    func newDeviceAvailableCallsFallbackWhenUnflagged() {
        let fixture = Fixture()
        _ = fixture.handler
        fixture.wasPlayingBeforeRouteDisconnect = false

        fixture.postRouteChange(reason: .newDeviceAvailable)

        #expect(fixture.playCalls.isEmpty)
        #expect(fixture.routeChangeRestartFallbackCount == 1)
    }

    // MARK: - Route change: default

    @Test("Any other route-change reason calls the restart-fallback hook", arguments: [
        AVAudioSession.RouteChangeReason.categoryChange,
        .routeConfigurationChange,
        .override,
        .wakeFromSleep,
    ])
    func otherReasonsCallFallback(reason: AVAudioSession.RouteChangeReason) {
        let fixture = Fixture()
        _ = fixture.handler

        fixture.postRouteChange(reason: reason)

        #expect(fixture.routeChangeRestartFallbackCount == 1)
        #expect(fixture.stopCalls.isEmpty)
        #expect(fixture.playCalls.isEmpty)
    }

    // MARK: - Logging hooks

    @Test("onInterruptionReceived and onRouteChangeReceived fire exactly once per notification, with the right payload")
    func loggingHooksReceiveExactPayload() {
        let fixture = Fixture()
        _ = fixture.handler

        fixture.postInterruption(type: .began)
        fixture.postRouteChange(reason: .oldDeviceUnavailable)

        #expect(fixture.interruptionsReceived == [.began])
        #expect(fixture.routeChangesReceived == [.oldDeviceUnavailable])
    }

    // MARK: - Deinit tears down observers

    @Test("Deallocating the handler removes its notification observers")
    func deallocatingRemovesObservers() {
        var interruptionsReceived: [AVAudioSession.InterruptionType] = []
        let center = NotificationCenter()
        var localHandler: PlaybackInterruptionRouteHandler? = PlaybackInterruptionRouteHandler(
            notificationCenter: center,
            isPlaying: { false },
            sessionID: { nil },
            playbackDuration: { 0 },
            analytics: MockStructuredAnalytics(),
            stop: { _ in },
            play: { _ in },
            getWasPlayingBeforeRouteDisconnect: { false },
            setWasPlayingBeforeRouteDisconnect: { _ in },
            onInterruptionReceived: { interruptionsReceived.append($0) }
        )
        _ = localHandler

        center.post(InterruptionMessage(type: .began, options: []), subject: nil as AVAudioSession?)
        #expect(interruptionsReceived == [.began])

        localHandler = nil

        center.post(InterruptionMessage(type: .began, options: []), subject: nil as AVAudioSession?)
        #expect(interruptionsReceived == [.began], "No further delivery once the handler is deallocated")
    }
}
#endif
