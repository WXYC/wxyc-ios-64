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

    /// Whether a play request is still standing and still cancellable.
    /// See `PlaybackController`.
    ///
    /// Distinct from `isPlaying` here too: this controller reads its live
    /// player, which is not yet playing while a start is in flight. Both
    /// controllers must answer a tap the same way for the shared UI to be
    /// correct on either.
    ///
    /// The error carve-out matters most on watchOS, where a ramp that
    /// exhausts settles on `.error(.maxReconnectAttemptsExceeded)` and stops
    /// retrying with intent still set. Without it the control would sit on
    /// pause forever and a tap would stop a stream that is already dead,
    /// leaving no way to try again.
    public var isPlaybackRequested: Bool {
        playbackIntended && !state.isError
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
        heartbeatInterval: Duration = .seconds(60),
        heartbeatSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.radioPlayer = radioPlayer
        self.audioSession = audioSession
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatSleep = heartbeatSleep

        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: remoteCommandCenter)
        setUpPlayerStateObservation()
        setUpHeartbeat()
    }
    #else
    init(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(analytics: nil),
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default,
        heartbeatInterval: Duration = .seconds(60),
        heartbeatSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.radioPlayer = radioPlayer
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatSleep = heartbeatSleep

        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: nil)
        setUpPlayerStateObservation()
        setUpHeartbeat()
    }
    #endif

    @MainActor
    deinit {
        // interruptionRouteHandler's own deinit removes its notification
        // observers; nothing to do here beyond releasing the reference,
        // which happens automatically once this deinit body returns.
        if let stallObservation { notificationCenter.removeObserver(stallObservation) }
        reconnectTask?.cancel()
        heartbeat?.stop()
    }

    private func setUpObservations(
        notificationCenter: NotificationCenter,
        remoteCommandCenter: MPRemoteCommandCenter?
    ) {
        #if os(iOS) || os(tvOS)
        setUpInterruptionRouteHandler(notificationCenter: notificationCenter)
        #endif

        stallObservation = notificationCenter.addMainActorObserver(
            for: PlaybackStalledMessage.self
        ) { [weak self] _ in
            self?.handlePlaybackStalled()
        }

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
    
    /// Branches on `isPlaybackRequested` (intent) rather than `isPlaying`, so
    /// both controllers answer a tap identically — see the note on
    /// `AudioPlayerController.toggle(reason:)`.
    public func toggle(reason: PlaybackReason) throws {
        if self.isPlaybackRequested {
            stop(reason: reason)
        } else {
            try self.play(reason: reason)
        }
    }

    /// Ends the listen: captures a `PlaybackStoppedEvent` — attributing
    /// `source` from `reason` (#668) — and then tears playback down.
    ///
    /// Unlike `AudioPlayerController`'s, this capture is unconditional — there
    /// is no one-event-per-listen predicate here at all. The two controllers
    /// disagreeing about when a listen ends is #938; this rename only makes
    /// the disagreement visible by giving both methods the same name.
    ///
    /// The free-text `reason` string is deliberately
    /// withheld here (matches the pre-existing "user-initiated stops report a
    /// nil reason" contract), but `source` is never nil: every stop site
    /// knows its `PlaybackReason` even when it doesn't want to surface the
    /// free-text string. Shared by `toggle(reason:)`'s stop branch,
    /// `remotePauseOrStopCommand`, `remoteTogglePlayPauseCommand`'s stop
    /// branch, so all three paths stay identical — some of which are gated
    /// behind a real `MPRemoteCommandEvent` a unit test can't construct.
    public func stop(reason: PlaybackReason) {
        analytics.capture(PlaybackStoppedEvent(source: reason.playbackSource, duration: playbackTimer.duration(), sessionID: sessionID))
        self.tearDown(reason: reason)
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
        audioSessionActivated = true
        #endif

        analytics.capture(PlaybackStartedEvent(reason: reason.rawValue, source: reason.playbackSource, sessionID: sessionID))
        self.radioPlayer.play()
        // State transitions to .playing when radioPlayer.isPlaying becomes true
    }

    /// Stops playback without capturing analytics.
    /// Call sites should capture analytics BEFORE calling this method.
    ///
    /// Deliberately *not* carrying the `AudioPlayerController` idempotency
    /// guard added for #933 — a redundant stop there was expensive, and here it
    /// is mostly not. Two of that guard's three costs cannot arise in this
    /// controller as a matter of structure: it drives an `AVPlayer`, so there
    /// is no decoder to churn, and its `tearDown(reason:)` touches the audio
    /// session not at all (#778).
    ///
    /// The third — double-counting `PlaybackStoppedEvent` — is contingent
    /// rather than structural, and that distinction is the whole reason this
    /// note exists. `remotePauseOrStopCommand` reaches `stop`
    /// with no intent check ahead of it, and the iOS/tvOS initializers default
    /// `remoteCommandCenter` to `MPRemoteCommandCenter.shared()`, so on iOS
    /// that path is compiled, armed, and registered against the process-global
    /// command centre. watchOS builds this type with no command centre at all,
    /// leaving `toggle(reason:)` — already gated on `isPlaybackRequested` — as
    /// the only route in.
    ///
    /// Do not read the absence of a shipping iOS consumer as a guarantee:
    /// `PlayerControllerTestHarness.make(for: .radioPlayerController)` already
    /// constructs this controller under `#if os(iOS) || os(tvOS)` against the
    /// real `.shared()` centre. Anything that dispatches a remote pause to it
    /// double-counts, so add the guard when a consumer actually receives
    /// remote commands rather than treating this paragraph as the guard.
    ///
    /// - Parameter reason: Which stop this is. Not a telemetry field — this
    ///   method emits nothing. `PlaybackStopTeardown` reads it to tell an echo
    ///   from a new decision under the #665 session-survival rule, so passing a
    ///   convenient value rather than the true one changes teardown behaviour.
    public func tearDown(reason: PlaybackReason) {
        // Shared six-step teardown (#755): cancels the reconnect, resets
        // backoff, stops the heartbeat (an immediate cancellation guarantee
        // rather than waiting on the async state-stream round-trip below to
        // notice the player went idle), clears playback intent, and applies
        // the #665 sessionID-survival rule. See `PlaybackStopTeardown`.
        PlaybackStopTeardown.run(
            reason: reason,
            cancelReconnect: {
                reconnectTask?.cancel()
                reconnectTask = nil
            },
            resetBackoff: { backoffTimer.reset() },
            stopHeartbeat: { heartbeat?.stop() },
            playbackIntended: &playbackIntended,
            wasPlayingBeforeRouteDisconnect: &wasPlayingBeforeRouteDisconnect,
            sessionID: &sessionID,
            // watchOS builds this controller with no interruption handler at
            // all, so there is no pending resume to retire there.
            cancelPendingInterruptionResume: {
                #if os(iOS) || os(tvOS)
                interruptionRouteHandler?.cancelPendingInterruptionResume()
                #endif
            }
        )
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
    /// Owns the interruption/route-change notification subscription, the
    /// case switch, and the shared `PlaybackStoppedEvent` capture (#756),
    /// extracted into `PlaybackCore` so both this controller and
    /// `AudioPlayerController` compose the same implementation instead of
    /// each maintaining a duplicated copy. Populated by
    /// `setUpInterruptionRouteHandler()`.
    private var interruptionRouteHandler: PlaybackInterruptionRouteHandler?
    #endif
    private var stallObservation: (any NSObjectProtocol)?
    
    #if os(iOS) || os(tvOS)
    private let audioSession: AudioSessionProtocol
    /// Whether `play(reason:)` last succeeded in activating `audioSession`.
    ///
    /// The background handback is guarded on this so the controller never
    /// deactivates — and, via `.notifyOthersOnDeactivation`, fans a resume out
    /// to every other audio app over — a session it never took. Mirrors
    /// `AudioPlayerController.audioSessionActivated`.
    private var audioSessionActivated = false
    #endif
    
    private var playbackTimer = Timer.start()
    internal var backoffTimer: ExponentialBackoff
    private var reconnectTask: Task<Void, Never>?

    private let analytics: AnalyticsService
    private var stallStartTime: Date?
    /// Whether playback was active immediately before the last route
    /// disconnect (e.g. headphones unplugged), so a later reconnect knows
    /// whether to resume. `wasPlayingBeforeInterruption` has no equivalent
    /// field here — it moved entirely into `PlaybackInterruptionRouteHandler`
    /// (#756), since neither controller read it outside interruption
    /// handling. This flag stays controller-owned because `play()` and
    /// `PlaybackStopTeardown` also touch it.
    ///
    /// `package`, not `private`, so `PlaybackInterruptionRouteHandler` can
    /// read and write it through `PlaybackInterruptionContext` conformance
    /// (#804) — the same read/write access it already had via the
    /// `getWasPlayingBeforeRouteDisconnect`/`setWasPlayingBeforeRouteDisconnect`
    /// closures this replaced, just narrowed to the `Playback` package rather
    /// than exposed as an anonymous closure pair.
    package var wasPlayingBeforeRouteDisconnect = false
    private var playbackIntended = false
    /// Stable per-listen identifier (#665), generated at the play intent
    /// alongside `playbackTimer` and threaded onto every playback analytics
    /// event so one continuous listen can be reconstructed from the event
    /// stream. Cleared in `stop()` — except for the interruption and
    /// route-disconnect reasons, which stop playback only as a prelude to an
    /// imminent auto-resume and must preserve the id (see `tearDown(reason:)`).
    ///
    /// Getter is `package` so `PlaybackInterruptionRouteHandler` can read it
    /// through `PlaybackInterruptionContext` conformance (#804); the setter
    /// stays `private` — nothing outside this controller ever wrote it,
    /// including the handler, which only ever read it via a `() -> String?`
    /// closure.
    package private(set) var sessionID: String?
    /// Cadence at which `playback_heartbeat` fires while playing (#666). See
    /// `AudioPlayerController.heartbeatInterval` for the interval choice and
    /// budget rationale, which applies identically here.
    private let heartbeatInterval: Duration
    /// The sleep behind each `playback_heartbeat` tick. See
    /// `AudioPlayerController.heartbeatSleep` for the rationale, which
    /// applies identically here (#815).
    private let heartbeatSleep: @Sendable (Duration) async throws -> Void
    /// Owns the `playback_heartbeat` cancel-then-loop-sleep-emit task shape
    /// (#666), extracted into `PlaybackCore` so both this controller and
    /// `AudioPlayerController` compose the same implementation instead of
    /// each maintaining a byte-identical copy (#755). Populated by
    /// `setUpHeartbeat()`, called at the end of `init` — its `onTick`
    /// closure captures `self` weakly, which Swift only permits once every
    /// other stored property has a value.
    private var heartbeat: PlaybackHeartbeat?
    /// Whether the app is foregrounded, read by `emitHeartbeat()` for the
    /// heartbeat's `context` field.
    ///
    /// Nothing in the shipping app ever sets this to `false`. The only writes
    /// are in the `#if os(iOS)` `handleApplicationDidEnterBackground()` /
    /// `handleApplicationWillEnterForeground()` methods below, reached through
    /// the `PlaybackController` protocol's `#if os(iOS)`-gated requirements —
    /// and no iOS scene drives this controller (`WXYCApp` uses
    /// `AudioPlayerController`), while watchOS, the one platform that does
    /// (`RadioPlayerController.shared` backs `WatchXYCApp`), compiles both the
    /// requirement and the methods out. So a watchOS heartbeat always reports
    /// `.foreground` — closing that gap needs a watchOS-native lifecycle
    /// signal (`WKExtension` / SwiftUI `scenePhase`) and is out of scope here;
    /// see the PR description.
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
    /// Constructs the shared `PlaybackInterruptionRouteHandler` (#756). This
    /// controller's genuine extras beyond the shared switch: an
    /// `InterruptionEvent` capture alongside the shared `PlaybackStoppedEvent`
    /// on a `.began` that actually stops active playback, the `.interrupted`
    /// state transition on every `.began`, and — at both the
    /// `.newDeviceAvailable`-without-a-prior-disconnect branch and every other
    /// route-change reason — a restart of the wrapped player if it stopped
    /// while playback was still intended. `AudioPlayerController`'s
    /// `reactivateAfterInterruptionIfPending()` equivalent has no counterpart
    /// here, so `onInterruptionEndedWithoutResume` is left at its no-op default.
    func setUpInterruptionRouteHandler(notificationCenter: NotificationCenter) {
        interruptionRouteHandler = PlaybackInterruptionRouteHandler(
            notificationCenter: notificationCenter,
            context: self,
            analytics: analytics,
            onInterruptionReceived: { type in
                Log(.info, category: .playback, "Session interrupted: type=\(type.rawValue)")
            },
            onInterruptionWillStopForPlayback: { [weak self] in
                guard let self else { return }
                analytics.capture(InterruptionEvent(type: .began, sessionID: self.sessionID))
            },
            onInterruptionBeganHandled: { [weak self] in self?.state = .interrupted },
            onRouteChangeReceived: { reason in
                Log(.info, category: .playback, "Session route changed: reason=\(reason.rawValue)")
            },
            onRouteChangeRestartFallback: { [weak self] in
                guard let self else { return }
                if self.playbackIntended && !self.radioPlayer.isPlaying {
                    self.radioPlayer.play()
                }
            }
        )
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
    /// `setUpPlayerStateObservation()`). Delegates to the shared
    /// `PlaybackHeartbeat` component (#755); see that type for the
    /// cancel-then-loop-sleep-emit implementation and its lifetime guarantees.
    func startHeartbeat() {
        heartbeat?.start()
    }

    /// Stops the heartbeat cadence. Idempotent. Called on every transition
    /// away from `.playing` in `setUpPlayerStateObservation()`, and
    /// explicitly from `tearDown(reason:)` for an immediate cancellation
    /// guarantee.
    func stopHeartbeat() {
        heartbeat?.stop()
    }

    /// Creates the `PlaybackHeartbeat` component. Called at the end of
    /// `init` because its `onTick` closure captures `self` weakly, which
    /// Swift only permits once every stored property already has a value.
    func setUpHeartbeat() {
        heartbeat = PlaybackHeartbeat(interval: heartbeatInterval, sleep: heartbeatSleep) { [weak self] in
            self?.emitHeartbeat()
        }
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
    /// Hands the audio session back when the app backgrounds without playback
    /// intended.
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
    /// `AudioPlayerController.tearDown(reason:)`, on the pause-button tap path.
    /// This controller's `tearDown(reason:)` touches the session not at all, so
    /// that half of #773 has no counterpart here.
    ///
    /// Nothing reaches this today, on any platform. `WXYCApp` and `WXYCTVApp`
    /// both drive `AudioPlayerController.shared`; the only runtime consumer of
    /// `RadioPlayerController.shared` is `WatchXYCApp`, and watchOS compiles
    /// this `#if os(iOS)` block out. Removing #788's `NotificationCenter`
    /// observers took away the last live entry point, leaving the
    /// `PlaybackController` requirement above as the only door — one no iOS
    /// scene currently opens. That is why none of this is urgent; it is not
    /// why the shape below is right.
    ///
    /// Note the platform gates differ: this block is `#if os(iOS)` while the
    /// matching activation in `play(reason:)` sits inside a wider
    /// `#if os(iOS) || os(tvOS)`. Widening one does not widen the other.
    ///
    /// Two guards, both matching `AudioPlayerController`:
    ///
    /// - **Intent, not actual state.** `isPlaying` is false for the whole
    ///   buffering window between `play()`'s `setActive(true, …)` and audio
    ///   actually rendering, so the `isPlaying` guard this replaced tore down
    ///   the session a pending `play()` had just activated whenever the user
    ///   backgrounded right after hitting play. `playbackIntended` covers that
    ///   window. It is broader than the window, not equal to it: it is set in
    ///   `play(reason:)` and cleared only in `tearDown(reason:)`, so it also
    ///   survives a stall and a backoff exhaustion. Holding the session across
    ///   a dead stream is deliberate and is what
    ///   `handleApplicationWillEnterForeground()` below relies on to recover.
    /// - **Only hand back what was taken.** `audioSessionActivated` keeps the
    ///   handback from deactivating a session this controller never activated
    ///   — which, because of `.notifyOthersOnDeactivation`, would fan a resume
    ///   out to every other audio app over a session it never owned.
    ///
    /// `RadioPlayerControllerBackgroundBehaviorTests` pins all of it —
    /// synchronous, skipped whenever playback is intended, and skipped when
    /// there is nothing to hand back. See #777, #788.
    func handleApplicationDidEnterBackground() {
        isForegrounded = false

        guard !self.playbackIntended, audioSessionActivated else {
            return
        }

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActivated = false
        } catch {
            analytics.capture(Analytics.ErrorEvent(error: error, context: "RadioPlayerController could not deactivate"))
            Log(.error, category: .playback, "RadioPlayerController could not deactivate: \(error)")
        }
    }

    /// Reconciles on the way back in, keyed off the same intent the
    /// backgrounding handback is guarded on.
    ///
    /// The two halves have to read the same predicate or they undo each other:
    /// guarding the background half on intent while this one guarded on
    /// `isPlaying` meant a play that was still buffering survived the
    /// backgrounding only to be stopped — with a `PlaybackStoppedEvent` — the
    /// moment the app came back. Same user-visible outcome as the bug #788
    /// fixed, one transition later.
    ///
    /// With intent on record there are two cases, mirroring
    /// `AudioPlayerController.handleAppWillEnterForeground()`:
    ///
    /// - **Stranded** — idle or terminally errored with no reconnect in
    ///   flight, which is where a backoff exhaustion leaves things. Re-drive
    ///   the full play path so the session activation and the player start
    ///   both happen. This is the recovery that makes holding the session
    ///   across a dead stream sound rather than a leak.
    /// - **Otherwise** — playing, buffering, or actively reconnecting. Only
    ///   re-affirm the session: restarting would cancel a healthy reconnect,
    ///   discard backoff progress, and emit a spurious playback-start.
    ///
    /// With no intent on record there is nothing to reconcile. The
    /// `stop(reason: .foregroundNotPlaying)` that used to run
    /// here fired on every foreground transition of an idle app, stopping an
    /// already-stopped player and emitting a stop event for a listen that had
    /// already ended.
    func handleApplicationWillEnterForeground() {
        isForegrounded = true

        guard playbackIntended else { return }

        if (state.isIdle || state.isError), reconnectTask == nil {
            try? self.play(reason: .resumeAfterForeground)
        } else {
            reactivateAudioSession()
        }
    }

    /// Re-asserts the audio session without disturbing playback, for a
    /// foreground transition where a play is already under way.
    func reactivateAudioSession() {
        do {
            try audioSession.setActive(true, options: [])
            audioSessionActivated = true
        } catch {
            analytics.capture(Analytics.ErrorEvent(error: error, context: "RadioPlayerController could not reactivate"))
            Log(.error, category: .playback, "RadioPlayerController could not reactivate: \(error)")
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
        stop(reason: .remotePauseCommand)

        return .success
    }

    /// Delegates to `toggle(reason:)` rather than repeating its branch, for the
    /// same reason `remotePauseOrStopCommand` routes through
    /// `stop`: this path is gated behind a real
    /// `MPRemoteCommandEvent` a unit test can't construct, so any logic that
    /// lives here is logic nothing can check. It previously branched on
    /// `radioPlayer.isPlaying`, which meant the lock screen and the on-screen
    /// button disagreed about what a tap does while a start is in flight —
    /// exactly the split this predicate exists to close.
    func remoteTogglePlayPauseCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            try self.toggle(reason: .remoteToggleCommand)

            return .success
        } catch {
            return .commandFailed
        }
    }
}

// MARK: - PlaybackInterruptionContext Conformance (#804)

#if os(iOS) || os(tvOS)
extension RadioPlayerController: PlaybackInterruptionContext {
    /// `isPlaying`, `sessionID`, `wasPlayingBeforeRouteDisconnect`,
    /// `tearDown(reason:)`, and `play(reason:)` are satisfied by the members
    /// declared above (the first three widened from `private` to `package`
    /// so `PlaybackInterruptionRouteHandler` can read/write them through this
    /// conformance). `playbackDuration` has no controller-owned equivalent —
    /// unlike `AudioPlayerController`, this controller only ever derived it
    /// inline from `playbackTimer` — so it's added here, package-scoped,
    /// purely for this conformance.
    package var playbackDuration: TimeInterval { playbackTimer.duration() }
}
#endif
