//
//  RadioPlayerController.swift
//  Playback
//
//  High-level controller for RadioPlayer with system integration.
//
//  Created by Jake Bromberg on 03/26/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import Logger
import SwiftUI
import Core
import PlaybackCore
import Analytics
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
public final class RadioPlayerController: PlaybackController {
    #if os(iOS) || os(tvOS)
    public static let shared = RadioPlayerController(
        audioSession: AVAudioSession.sharedInstance(),
        remoteCommandCenter: .shared()
    )
    #else
    public static let shared = RadioPlayerController()
    #endif

    // MARK: - PlaybackController Protocol
    
    private let streamURL = RadioStation.WXYC.streamURL
    
    /// The current playback state
    public private(set) var state: PlaybackState = .idle

    public var isPlaying: Bool {
        self.radioPlayer.isPlaying
    }

    public var isLoading: Bool {
        // RadioPlayerController doesn't track loading state separately
        false
    }

    // Note: the wrapped `RadioPlayer` is always constructed with its own
    // analytics sink explicitly nil — this controller is the sole emitter of
    // playback analytics. `RadioPlayer`'s convenience init previously
    // defaulted to the real, shared analytics service, which double-counted
    // every "play" on top of this controller's own capture — the root cause
    // of watchOS always double-counting plays, since the watch app
    // exclusively uses this controller. See #669.
    #if os(iOS) || os(tvOS)
    public convenience init(
        audioSession: AudioSessionProtocol = AVAudioSession.sharedInstance(),
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.init(
            radioPlayer: RadioPlayer(analytics: nil),
            audioSession: audioSession,
            notificationCenter: notificationCenter,
            analytics: StructuredPostHogAnalytics.shared,
            remoteCommandCenter: remoteCommandCenter
        )
    }
    #else
    public convenience init(
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            radioPlayer: RadioPlayer(analytics: nil),
            notificationCenter: notificationCenter,
            analytics: StructuredPostHogAnalytics.shared
        )
    }
    #endif

    #if os(iOS) || os(tvOS)
    init(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(analytics: nil),
        audioSession: AudioSessionProtocol = AVAudioSession.sharedInstance(),
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        remoteCommandCenter: MPRemoteCommandCenter = .shared(),
        backoffTimer: ExponentialBackoff = .default,
        heartbeatInterval: Duration = .seconds(60)
    ) {
        self.radioPlayer = radioPlayer
        self.audioSession = audioSession
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.heartbeatInterval = heartbeatInterval

        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: remoteCommandCenter)
        setUpPlayerStateObservation()
    }
    #else
    init(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(analytics: nil),
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default,
        heartbeatInterval: Duration = .seconds(60)
    ) {
        self.radioPlayer = radioPlayer
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.heartbeatInterval = heartbeatInterval

        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: nil)
        setUpPlayerStateObservation()
    }
    #endif

    @MainActor
    deinit {
        #if os(iOS) || os(tvOS)
        if let interruptionObservation { notificationCenter.removeObserver(interruptionObservation) }
        if let routeChangeObservation { notificationCenter.removeObserver(routeChangeObservation) }
        #endif
        if let stallObservation { notificationCenter.removeObserver(stallObservation) }
        #if os(iOS)
        if let backgroundObservation { notificationCenter.removeObserver(backgroundObservation) }
        if let foregroundObservation { notificationCenter.removeObserver(foregroundObservation) }
        #endif
        reconnectTask?.cancel()
        heartbeatTask?.cancel()
    }

    private func setUpObservations(
        notificationCenter: NotificationCenter,
        remoteCommandCenter: MPRemoteCommandCenter?
    ) {
        #if os(iOS) || os(tvOS)
        interruptionObservation = notificationCenter.addMainActorObserver(
            for: InterruptionMessage.self
        ) { [weak self] message in
            self?.handleSessionInterrupted(message)
        }
        routeChangeObservation = notificationCenter.addMainActorObserver(
            for: RouteChangeMessage.self
        ) { [weak self] message in
            self?.handleRouteChanged(message)
        }
        #endif

        stallObservation = notificationCenter.addMainActorObserver(
            for: PlaybackStalledMessage.self
        ) { [weak self] _ in
            self?.handlePlaybackStalled()
        }

        #if os(iOS)
        backgroundObservation = notificationCenter.addMainActorObserver(
            for: AppDidEnterBackgroundMessage.self
        ) { [weak self] _ in
            self?.handleApplicationDidEnterBackground()
        }
        foregroundObservation = notificationCenter.addMainActorObserver(
            for: AppWillEnterForegroundMessage.self
        ) { [weak self] _ in
            self?.handleApplicationWillEnterForeground()
        }
        #endif

        if let remoteCommandCenter {
            remoteCommandCenter.playCommand.addTarget(handler: self.remotePlayCommand)
            remoteCommandCenter.pauseCommand.addTarget(handler: self.remotePauseOrStopCommand)
            remoteCommandCenter.stopCommand.addTarget(handler: self.remotePauseOrStopCommand)
            remoteCommandCenter.togglePlayPauseCommand.addTarget(handler: self.remoteTogglePlayPauseCommand(_:))
        }
    }

    /// Callback fired when player state observation has started. Used by tests for synchronization.
    var onObserversReady: (() -> Void)?

    private func setUpPlayerStateObservation() {
        // Observe radioPlayer state and derive controller state
        Task { [weak self] in
            guard let self else { return }

            // Signal that observer is ready before entering the loop
            self.onObserversReady?()

            for await playerState in self.radioPlayer.stateStream {
                // Don't overwrite controller-specific states like .interrupted
                guard self.state != .interrupted else { continue }

                // Map PlayerState to PlaybackState
                // PlayerState doesn't include .interrupted (controller-level concern)
                let mappedState = playerState.asPlaybackState
                self.state = mappedState

                // Start/stop the `playback_heartbeat` cadence (#666) off the
                // same mapped state: only `.playing` means audio is actually
                // rendering, so a stall, error, or idle transition stops the
                // cadence, and a later recovery to `.playing` resumes it.
                if mappedState == .playing {
                    self.startHeartbeat()
                } else {
                    self.stopHeartbeat()
                }
            }
        }
    }
    
    // MARK: Public methods
    
    public func toggle(reason: PlaybackReason) throws {
        if self.isPlaying {
            stopWithAnalytics(reason: reason)
        } else {
            try self.play(reason: reason)
        }
    }

    /// Captures a `PlaybackStoppedEvent` — attributing `source` from `reason`
    /// (#668) — and then stops. The free-text `reason` string is deliberately
    /// withheld here (matches the pre-existing "user-initiated stops report a
    /// nil reason" contract), but `source` is never nil: every stop site
    /// knows its `PlaybackReason` even when it doesn't want to surface the
    /// free-text string. Shared by `toggle(reason:)`'s stop branch,
    /// `remotePauseOrStopCommand`, `remoteTogglePlayPauseCommand`'s stop
    /// branch, and `handleApplicationWillEnterForeground`'s reconciliation
    /// stop, so all four paths stay identical — some of which are gated
    /// behind a real `MPRemoteCommandEvent` a unit test can't construct.
    private func stopWithAnalytics(reason: PlaybackReason) {
        analytics.capture(PlaybackStoppedEvent(source: reason.playbackSource, duration: playbackTimer.duration(), sessionID: sessionID))
        self.stop(reason: reason)
    }

    public func play(reason: PlaybackReason) throws {
        self.state = .loading
        self.playbackTimer = Timer.start()
        self.playbackIntended = true
        self.wasPlayingBeforeRouteDisconnect = false
        sessionID = sessionID ?? UUID().uuidString

        #if os(iOS) || os(tvOS)
        do {
            try audioSession.setActive(true, options: [])
        } catch {
            self.state = .error(.audioSessionActivationFailed(error.localizedDescription))
            self.playbackIntended = false
            analytics.capture(PlaybackStoppedEvent(
                reason: "audio session activation failed",
                source: reason.playbackSource,
                duration: 0,
                sessionID: sessionID
            ))
            Log(.error, category: .playback, "RadioPlayerController could not start playback: \(error)")
            return
        }
        #endif

        analytics.capture(PlaybackStartedEvent(reason: reason.rawValue, source: reason.playbackSource, sessionID: sessionID))
        self.radioPlayer.play()
        // State transitions to .playing when radioPlayer.isPlaying becomes true
    }

    /// Stops playback without capturing analytics.
    /// Call sites should capture analytics BEFORE calling this method.
    /// - Parameter reason: Why playback was stopped (for analytics)
    public func stop(reason: PlaybackReason) {
        reconnectTask?.cancel()
        reconnectTask = nil
        backoffTimer.reset()
        // Immediate cancellation guarantee (#666), rather than waiting on the
        // async state-stream round-trip below to notice the player went idle.
        stopHeartbeat()
        self.playbackIntended = false
        if reason != .routeDisconnected {
            self.wasPlayingBeforeRouteDisconnect = false
        }
        // Interruption/route-disconnect stops are an implementation detail of
        // "pause, then auto-resume" — the listen itself isn't over, so the
        // session id must survive them. Any other reason is a genuine end of
        // the listen; the next `play()` mints a fresh id. See #665.
        if reason != .interruptionBegan && reason != .routeDisconnected {
            sessionID = nil
        }
        self.radioPlayer.stop()
        self.state = .idle
    }
    
    public func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        // RadioPlayerController uses AVPlayer which doesn't provide raw audio buffers
        // Return empty stream that finishes immediately
        AsyncStream { $0.finish() }
    }
    
    /// No-op: AVPlayer-based RadioPlayerController doesn't support render tap
    public func installRenderTap() {
        // AVPlayer doesn't expose raw audio buffers
    }

    /// No-op: AVPlayer-based RadioPlayerController doesn't support render tap
    public func removeRenderTap() {
        // AVPlayer doesn't expose raw audio buffers
    }
    
    #if os(iOS)
    public func handleAppDidEnterBackground() {
        handleApplicationDidEnterBackground()
    }

    public func handleAppWillEnterForeground() {
        handleApplicationWillEnterForeground()
    }
    #endif

    // MARK: Private

    /// `internal` (not `private`) so tests (`@testable import`) can downcast
    /// to the concrete player type and assert `hasAnalyticsSink == false` —
    /// this controller is expected to be the sole emitter of playback
    /// analytics (#669).
    let radioPlayer: any AudioPlayerProtocol
    private let notificationCenter: NotificationCenter
    #if os(iOS) || os(tvOS)
    private var interruptionObservation: (any NSObjectProtocol)?
    private var routeChangeObservation: (any NSObjectProtocol)?
    #endif
    private var stallObservation: (any NSObjectProtocol)?
    #if os(iOS)
    private var backgroundObservation: (any NSObjectProtocol)?
    private var foregroundObservation: (any NSObjectProtocol)?
    #endif
    
    #if os(iOS) || os(tvOS)
    private let audioSession: AudioSessionProtocol
    #endif
    
    private var playbackTimer = Timer.start()
    internal var backoffTimer: ExponentialBackoff
    private var reconnectTask: Task<Void, Never>?

    private let analytics: AnalyticsService
    private var stallStartTime: Date?
    private var wasPlayingBeforeInterruption = false
    private var wasPlayingBeforeRouteDisconnect = false
    private var playbackIntended = false
    /// Stable per-listen identifier (#665), generated at the play intent
    /// alongside `playbackTimer` and threaded onto every playback analytics
    /// event so one continuous listen can be reconstructed from the event
    /// stream. Cleared in `stop()` — except for the interruption and
    /// route-disconnect reasons, which stop playback only as a prelude to an
    /// imminent auto-resume and must preserve the id (see `stop(reason:)`).
    private var sessionID: String?
    /// Cadence at which `playback_heartbeat` fires while playing (#666). See
    /// `AudioPlayerController.heartbeatInterval` for the interval choice and
    /// budget rationale, which applies identically here.
    private let heartbeatInterval: Duration
    private var heartbeatTask: Task<Void, Never>?
    /// Whether the app is foregrounded, read by `emitHeartbeat()` for the
    /// heartbeat's `context` field. Updated only where this controller has
    /// lifecycle wiring — the `#if os(iOS)` `UIApplication` notification
    /// handlers below. On watchOS, where this controller is actually used in
    /// production (`RadioPlayerController.shared` backs `WatchXYCApp`),
    /// nothing ever sets this to `false`: `AppDidEnterBackgroundMessage` /
    /// `AppWillEnterForegroundMessage` are themselves `#if os(iOS)`-gated
    /// (see `UIApplicationMessages.swift`), since they're backed by
    /// `UIApplication`, which doesn't exist on watchOS. So a watchOS
    /// heartbeat always reports `.foreground` — closing that gap needs a
    /// watchOS-native lifecycle signal (`WKExtension` / SwiftUI
    /// `scenePhase`) and is out of scope here; see the PR description.
    private var isForegrounded = true
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers

    func handlePlaybackStalled() {
        Log(.error, category: .playback, "Playback stalled")

        self.state = .stalled
        self.stallStartTime = Date()

        // Deliberately does NOT capture a `pause` event (#667): a stall is not
        // a session end, and the previous "stalled"-reason `PlaybackStoppedEvent`
        // here double-counted the same elapsed seconds into the `pause.duration`
        // average once per stall in a stally session. The reliability signal
        // already lives in `StallRecoveryEvent` / `StreamErrorEvent`.
        //
        // Stop the heartbeat explicitly (#666) rather than relying solely on
        // `radioPlayer.stateStream`: `radioPlayer.stop()` below only pushes a
        // state-stream update when the underlying player's auto-update is
        // enabled, so listener-side silence must cancel the cadence here
        // directly. `startHeartbeat()` resumes it once a genuine recovery
        // reaches `.playing` again via the state stream.
        stopHeartbeat()
        self.radioPlayer.stop()
        self.attemptReconnectWithExponentialBackoff()
    }

#if os(iOS) || os(tvOS)
    func handleSessionInterrupted(_ message: InterruptionMessage) {
        Log(.info, category: .playback, "Session interrupted: type=\(message.type.rawValue)")

        switch message.type {
        case .began:
            // Per Apple's guidance: always stop on interruption began
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                analytics.capture(InterruptionEvent(type: .began, sessionID: sessionID))
                analytics.capture(PlaybackStoppedEvent(reason: PlaybackReason.interruptionBegan.rawValue, source: PlaybackReason.interruptionBegan.playbackSource, duration: playbackTimer.duration(), sessionID: sessionID))
                self.stop(reason: .interruptionBegan)
            }
            self.state = .interrupted

        case .ended:
            if message.options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                try? self.play(reason: .resumeAfterInterruption)
            }
            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    func handleRouteChanged(_ message: RouteChangeMessage) {
        Log(.info, category: .playback, "Session route changed: reason=\(message.reason.rawValue)")

        switch message.reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - stop playback per Apple HIG
            wasPlayingBeforeRouteDisconnect = isPlaying
            if isPlaying {
                analytics.capture(PlaybackStoppedEvent(reason: PlaybackReason.routeDisconnected.rawValue, source: PlaybackReason.routeDisconnected.playbackSource, duration: playbackTimer.duration(), sessionID: sessionID))
                self.stop(reason: .routeDisconnected)
            }

        case .newDeviceAvailable:
            // Device reconnected (e.g., AirPod reinserted) - resume if we were playing before disconnect
            if wasPlayingBeforeRouteDisconnect {
                try? self.play(reason: .resumeAfterRouteReconnect)
            } else if playbackIntended && !radioPlayer.isPlaying {
                radioPlayer.play()
            }

        default:
            // For all other route changes, check if playback was intended but
            // the player stopped unexpectedly. Restart if needed.
            if playbackIntended && !radioPlayer.isPlaying {
                radioPlayer.play()
            }
        }
    }
#endif

    private func attemptReconnectWithExponentialBackoff() {
        guard let waitTime = self.backoffTimer.nextWaitTime() else {
            // Backoff exhausted - capture error analytics
            let stallDuration = stallStartTime.map { Date().timeIntervalSince($0) }
            analytics.capture(StreamErrorEvent(
                playerType: .radioPlayer,
                errorType: .backoffExhausted,
                errorDescription: "Maximum reconnection attempts (\(backoffTimer.maximumAttempts)) exhausted",
                reconnectAttempts: Int(backoffTimer.numberOfAttempts),
                sessionDuration: playbackTimer.duration(),
                stallDuration: stallDuration,
                recoveryMethod: .retryWithBackoff,
                sessionID: sessionID
            ))
            Log(.info, category: .playback, "Backoff exhausted after \(self.backoffTimer.numberOfAttempts) attempts, giving up reconnection.")
            self.state = .error(.maxReconnectAttemptsExceeded)
            self.backoffTimer.reset()
            return
        }
        Log(.info, category: .playback, "Attempting to reconnect with exponential backoff \(self.backoffTimer).")
        reconnectTask = Task {
            if self.radioPlayer.isPlaying {
                captureRecoveryIfNeeded()
                self.backoffTimer.reset()
                return
            }

            do {
                self.radioPlayer.play()
                try await Task.sleep(nanoseconds: waitTime.nanoseconds)

                guard !Task.isCancelled else { return }
                if !radioPlayer.isPlaying {
                    attemptReconnectWithExponentialBackoff()
                } else {
                    captureRecoveryIfNeeded()
                    self.backoffTimer.reset()
                }
            } catch {
                self.backoffTimer.reset()
                return
            }
        }
    }

    private func captureRecoveryIfNeeded() {
        guard let stallStart = self.stallStartTime else { return }
        analytics.capture(StallRecoveryEvent(
            playerType: .radioPlayer,
            successful: true,
            attempts: Int(self.backoffTimer.numberOfAttempts),
            stallDuration: Date().timeIntervalSince(stallStart),
            reason: .bufferUnderrun,
            recoveryMethod: .retryWithBackoff,
            sessionID: sessionID
        ))
        self.stallStartTime = nil
    }

    // MARK: - Playback Heartbeat (#666)

    /// Starts (or restarts) the periodic `playback_heartbeat` cadence. Called
    /// only when the observed player state maps to `.playing` (see
    /// `setUpPlayerStateObservation()`), mirroring
    /// `AudioPlayerController.startHeartbeat()` — see that type for the full
    /// design rationale (interval choice, budget, idempotency).
    func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, interval = heartbeatInterval] in
            while true {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    // Cancelled mid-sleep.
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.emitHeartbeat()
            }
        }
    }

    /// Stops the heartbeat cadence and cancels its task. Idempotent. Called
    /// on every transition away from `.playing` in
    /// `setUpPlayerStateObservation()`, and explicitly from `stop(reason:)`
    /// for an immediate cancellation guarantee.
    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Captures one `PlaybackHeartbeatEvent` using the same monotonic
    /// `playbackTimer` duration as `pause.duration` and the same `sessionID`
    /// threaded onto every other playback event.
    private func emitHeartbeat() {
        analytics.capture(PlaybackHeartbeatEvent(
            sessionID: sessionID,
            cumulativeSeconds: playbackTimer.duration(),
            context: isForegrounded ? .foreground : .background,
            playerType: .radioPlayer
        ))
    }

    // MARK: External playback command handlers

#if os(iOS)
    /// Hands the audio session back when the app backgrounds without playing.
    ///
    /// The `setActive(false, …)` below is deliberately left on the caller's
    /// turn. That call is a blocking XPC round-trip to `mediaserverd` which,
    /// because of `.notifyOthersOnDeactivation`, also fans resume
    /// notifications out to every other audio app before returning, and #773
    /// traced a roughly one-second main-actor freeze to it. #777 asked whether
    /// #774's deferred handback should therefore be ported here. It should
    /// not, and the reason is not that this code is unreachable — that is only
    /// the reason it is not urgent.
    ///
    /// **A backgrounding handback belongs on the caller's turn.** Deferring it
    /// buys nothing: no view is rendering during a background transition, so
    /// there is no latency anyone can perceive. And it costs a guarantee — a
    /// deferred handback races app suspension, and if it loses,
    /// `.notifyOthersOnDeactivation` never fires and whatever app WXYC
    /// interrupted stays silent until WXYC is next resumed. #774 reaches the
    /// same conclusion for the identical call site on the other controller: it
    /// defers `stop()`'s handback but routes `handleAppDidEnterBackground()`
    /// through `deactivateAudioSessionOnCallersTurn()`, for exactly this
    /// reason. So this line already agrees with #774 rather than lagging it,
    /// and #776 — the residual race in the deferred path — is a hazard a port
    /// would *introduce* here, not one it would inherit.
    ///
    /// #773's visible symptom came from the blocking call in
    /// `AudioPlayerController.stop(reason:)`, on the pause-button tap path.
    /// This controller's `stop(reason:)` touches the session not at all, so
    /// that half of #773 has no counterpart here.
    ///
    /// Two further conditions make it moot today. Neither is visible from this
    /// line, and #777 exists because neither is guaranteed to keep holding:
    ///
    /// 1. **No iOS scene instantiates this controller.** `WXYCApp` and
    ///    `WXYCTVApp` both drive `AudioPlayerController.shared`; the only
    ///    runtime consumer of `RadioPlayerController.shared` is `WatchXYCApp`
    ///    (`WXYC/WatchXYC/WatchXYCApp.swift`). It was the iOS app's controller
    ///    until 8114d5c9 (2025-11-30), so this is a recent arrangement rather
    ///    than a long-standing one. Two caveats: `PlayerControllerType`'s
    ///    `.radioPlayer` case selects a *player* inside `AudioPlayerController`
    ///    and never this controller, so flipping that override does not reach
    ///    here; and `WXYC/WatchXYC/PlayerPage.swift` — a member of the WXYC TV
    ///    target as well as WatchXYC — names `.shared` in a `#Preview`, so the
    ///    type links into tvOS even though a lazy static reached only from a
    ///    preview registry is never instantiated by the shipping app.
    /// 2. **This block is `#if os(iOS)`.** watchOS, the one platform that does
    ///    instantiate the controller, compiles it out entirely, so the watch
    ///    never performs a handback at all. The matching activation in
    ///    `play(reason:)` sits inside a *wider* `#if os(iOS) || os(tvOS)` gate
    ///    — the two halves do not share a platform condition, so widening
    ///    either one does not implicitly widen the other.
    ///
    /// Either condition alone is insufficient, and the work to do if either
    /// changes is not "port #774". Two things here would need attention first,
    /// and neither is fixed by a deferred handback:
    ///
    /// - **Two entry points would both fire.** This runs from the
    ///   `AppDidEnterBackgroundMessage` observer *and* from the
    ///   `PlaybackController` requirement `handleAppDidEnterBackground()`
    ///   (see the passthrough above). `AudioPlayerController` deliberately has
    ///   only the latter, driven from SwiftUI's `scenePhase`. An iOS scene
    ///   wired to this controller would double-fire the handback.
    /// - **The guard is on the wrong predicate.** It reads `isPlaying`, actual
    ///   state, where `AudioPlayerController` reads `playbackIntended`, intent
    ///   — and this controller has `playbackIntended` too. Background during
    ///   buffering and `isPlaying` is still false, so this would tear down the
    ///   session the pending `play()` just activated at the `setActive(true,
    ///   …)` above.
    ///
    /// `RadioPlayerControllerBackgroundBehaviorTests` pins the current shape —
    /// synchronous, and skipped while playing — so that changing either is not
    /// silent. See #777.
    func handleApplicationDidEnterBackground() {
        isForegrounded = false

        guard !self.radioPlayer.isPlaying else {
            return
        }

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            analytics.capture(Analytics.ErrorEvent(error: error, context: "RadioPlayerController could not deactivate"))
            Log(.error, category: .playback, "RadioPlayerController could not deactivate: \(error)")
        }
    }

    func handleApplicationWillEnterForeground() {
        isForegrounded = true

        if self.radioPlayer.isPlaying {
            try? self.play(reason: .foregroundToggle)
        } else {
            stopWithAnalytics(reason: .foregroundNotPlaying)
        }
    }
#endif

    func remotePlayCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            try self.play(reason: .remotePlayCommand)
            return .success
        } catch {
            return .commandFailed
        }
    }

    func remotePauseOrStopCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        stopWithAnalytics(reason: .remotePauseCommand)

        return .success
    }

    func remoteTogglePlayPauseCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            if self.radioPlayer.isPlaying {
                stopWithAnalytics(reason: .remoteToggleCommand)
            } else {
                try self.play(reason: .remoteToggleCommand)
            }

            return .success
        } catch {
            return .commandFailed
        }
    }
}
