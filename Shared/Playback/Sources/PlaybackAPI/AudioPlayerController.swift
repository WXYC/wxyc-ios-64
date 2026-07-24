//
//  AudioPlayerController.swift
//  Playback
//
//  High-level audio player controller that handles system integration.
//  Works with any AudioPlayerProtocol implementation (MP3Streamer, RadioPlayer, etc.)
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AVFoundation
import Caching
import Core
import Foundation
import Logger
import MediaPlayer
import PlaybackCore
import Analytics
#if canImport(Intents)
import Intents
#endif
#if os(iOS)
import UIKit
#endif

// Platform-specific imports for default player
#if !os(watchOS)
import MP3StreamerModule
import HLSPlayerModule
#endif
import RadioPlayerModule

/// High-level controller for audio playback.
/// Handles audio session, remote commands, notifications, analytics, and system integration.
/// Works with any AudioPlayerProtocol implementation.
@MainActor
@Observable
public final class AudioPlayerController {

    // MARK: - Singleton

    #if os(iOS) || os(tvOS)
    public static let shared = AudioPlayerController(
        player: makePlayer(for: PlayerControllerType.loadPersisted()),
        audioSession: AVAudioSession.sharedInstance(),
        remoteCommandCenter: SystemRemoteCommandCenter(),
        notificationCenter: .default,
        analytics: StructuredPostHogAnalytics.shared,
        reachability: NWPathMonitorReachability()
    )
    #elseif os(watchOS)
    public static let shared = AudioPlayerController(
        player: RadioPlayer(),
        notificationCenter: .default,
        analytics: StructuredPostHogAnalytics.shared,
        reachability: NWPathMonitorReachability()
    )
    #else
    public static let shared = AudioPlayerController(
        player: makePlayer(for: PlayerControllerType.loadPersisted()),
        notificationCenter: .default,
        analytics: StructuredPostHogAnalytics.shared,
        reachability: NWPathMonitorReachability()
    )
    #endif

    // MARK: - Player Factory

    #if !os(watchOS)
    static func makePlayer(for type: PlayerControllerType) -> any AudioPlayerProtocol {
        switch type {
        case .mp3Streamer:
            MP3Streamer(configuration: MP3StreamerConfiguration(url: RadioStation.WXYC.streamURL))
        case .radioPlayer:
            RadioPlayer()
        case .hlsPlayer:
            HLSPlayer(url: HLSEnvironment.loadActive().url)
        }
    }
    #endif
    
    // MARK: - Public Properties

    /// Stored mirror of the underlying player state, updated via stateStream observation.
    /// Using a stored property (instead of reading player.state directly) allows the
    /// Observation framework to track mutations, since `player` is @ObservationIgnored.
    private var playerState: PlayerState = .idle

    /// Whether audio is currently playing
    public var isPlaying: Bool {
        playerState == .playing
    }

    /// Whether playback is loading (play initiated but not yet playing, or buffering)
    /// Excludes error and stopped states to prevent infinite loading
    public var isLoading: Bool {
        playbackIntended && (!isPlaying || playerState == .loading) && !playerState.isError
    }

    /// Single-line snapshot of internal state, intended for diagnostics (e.g.
    /// `Issue.record` on a test timeout). Captures the otherwise-private fields
    /// that distinguish "audio session activation failed" from "stream took
    /// too long to start" — see #251.
    public var debugStateSnapshot: String {
        "playerState=\(playerState), playbackIntended=\(playbackIntended), isPlaying=\(isPlaying), isLoading=\(isLoading), audioSessionActivated=\(audioSessionActivated), isForegrounded=\(isForegrounded), holdingPatternEngaged=\(holdingPatternEngaged), holdingReconnectInFlight=\(holdingReconnectInFlight), reachabilitySatisfied=\(lastReachabilitySatisfied.map(String.init(describing:)) ?? "nil"), holdingReconnectTrigger=\(holdingReconnectTrigger.rawValue)"
    }

    /// Whether the CPU-usage aggregation session is currently open. Exposed for
    /// tests asserting the "session follows playback intent, not transient
    /// errors" contract (#512): the session must stay open across backoff-ramp
    /// exhaustion so a later holding-pattern recovery still credits it.
    public var cpuSessionIsActive: Bool {
        #if os(watchOS)
        false
        #else
        cpuAggregator?.isSessionActive ?? false
        #endif
    }

    // MARK: - Dependencies
    // These are nonisolated(unsafe) to allow cleanup in deinit

    @ObservationIgnored private nonisolated(unsafe) var player: AudioPlayerProtocol
    @ObservationIgnored private nonisolated(unsafe) var notificationCenter: NotificationCenter
    @ObservationIgnored private nonisolated(unsafe) var analytics: AnalyticsService
    /// Backing store for the persisted stream-gain boost. `DefaultsStorage` is
    /// Sendable, so a plain `let` is safe across the controller's isolation.
    @ObservationIgnored private let defaults: DefaultsStorage

    #if os(iOS) || os(tvOS)
    @ObservationIgnored private nonisolated(unsafe) var audioSession: AudioSessionProtocol?
    @ObservationIgnored private nonisolated(unsafe) var remoteCommandCenter: RemoteCommandCenterProtocol?
    #endif

    // MARK: - State

    private var wasPlayingBeforeInterruption = false
    private var wasPlayingBeforeRouteDisconnect = false
    /// Tracks if we intend to be playing (survives transient state changes)
    private var playbackIntended = false
    /// Tracks whether the audio session has been activated (to avoid deactivating when never activated)
    private var audioSessionActivated = false
    /// Tracks when playback started for analytics duration reporting
    private var playbackStartTime: Date?
    private var stallStartTime: Date?
    @ObservationIgnored private var interruptionObservation: (any NSObjectProtocol)?
    @ObservationIgnored private var routeChangeObservation: (any NSObjectProtocol)?
    @ObservationIgnored private nonisolated(unsafe) var commandTargets: [Any] = []

    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var stateObservationTask: Task<Void, Never>?

    // Exponential backoff for reconnection
    @ObservationIgnored internal var backoffTimer: ExponentialBackoff
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?

    // Reachability-gated reconnect (#517). The signal gates and accelerates the
    // controller's uncapped holding pattern (#512) — the single owner of
    // reachability-driven prompt resume. When no reachability is injected, the
    // cached state stays `nil` and the holding pattern falls back to its blind
    // timed cadence, so behaviour is unchanged for callers that don't wire it.
    @ObservationIgnored private let reachability: NetworkReachability?
    @ObservationIgnored private var reachabilityMonitorTask: Task<Void, Never>?
    /// Cached path-satisfied state, updated by the reachability subscription.
    /// `nil` until the first signal arrives (or forever when reachability is not
    /// injected). The gate requires an explicit `true`, so a stale-optimistic
    /// seed can never fire a blind attempt on a known-down network.
    private var lastReachabilitySatisfied: Bool?
    /// Whether the uncapped holding phase (#512) is active. The bounded ramp is
    /// left un-gated (short, self-terminating); only this phase idles while
    /// unsatisfied and accelerates on the → satisfied edge.
    private var holdingPatternEngaged = false
    /// Whether a holding-pattern connect attempt is currently in flight, so a
    /// flapping → satisfied edge cannot launch an overlapping connect.
    private var holdingReconnectInFlight = false
    /// What triggered the *pending* holding-pattern attempt, so a successful
    /// recovery is attributed to the right path in telemetry (#517 nice-to-have):
    /// `.reachabilityResume` when a `→ satisfied` edge accelerated it,
    /// `.holdingFallback` when the flat timed cadence fired it. Snapshotted at the
    /// start of each attempt (before the `.playing` state observer can clear it
    /// via `leaveHoldingPattern()`) and passed to `captureRecoveryIfNeeded`.
    private var holdingReconnectTrigger: RecoveryMethod = .holdingFallback

    // Play-intent → first-audio watchdog (#518). Guards the whole intent→audio
    // span so the fully-silent startup class (session-activation abort, deferred
    // connect never running, `'!int'` retries exhausted) becomes visible
    // (`silent_startup`) and self-healing instead of stranding in silence.
    /// Deadline from play-intent to first audio. Must exceed the player's
    /// `startupTimeout` (MP3Streamer default 12s) so the inner
    /// connected-but-starved class (`startup_timeout`, #487) surfaces and
    /// disarms this outer watchdog first. Injected so tests can trigger it fast.
    private let startupWatchdogDeadline: Duration
    @ObservationIgnored private var startupWatchdogTask: Task<Void, Never>?

    #if os(iOS) || os(tvOS)
    // Bounded deferral for audio-session activation that fails with
    // `CannotInterruptOthers` ('!int'). Rather than fight a legitimate
    // interruption (e.g. an active phone call) with a busy-loop, we retry a
    // small number of times with a short delay, and also reactivate promptly
    // when the system posts an interruption-ended notification. See #514.
    @ObservationIgnored private var sessionActivationRetryTask: Task<Void, Never>?
    /// Whether a session activation is deferred pending the transient
    /// "can't interrupt other audio" state clearing.
    private var sessionActivationPending = false
    /// The play reason to resume with once a deferred activation succeeds.
    private var pendingPlaybackReason: PlaybackReason?
    /// Maximum number of deferred activation retries before giving up.
    private let maxSessionActivationRetries = 4
    /// Delay between deferred activation retries.
    private let sessionActivationRetryDelay: Duration = .milliseconds(250)
    #endif

    // CPU Session Aggregation
    @ObservationIgnored private var cpuAggregator: CPUSessionAggregator?
    private var isForegrounded = true
    
    // Render tap state for background/foreground management
    private var renderTapDesired = false
    
    // MARK: - Initialization

    #if os(iOS) || os(tvOS)
    /// Creates a controller with injected dependencies (iOS/tvOS)
    /// - Parameters:
    ///   - player: The audio player implementation to use
    ///   - audioSession: Audio session for managing system audio behavior
    ///   - remoteCommandCenter: Remote command center for Lock Screen/Control Center integration
    ///   - notificationCenter: Notification center for system notifications
    ///   - analytics: Analytics service for playback events
    ///   - backoffTimer: Exponential backoff timer for reconnection attempts
    public init(
        player: AudioPlayerProtocol,
        audioSession: AudioSessionProtocol?,
        remoteCommandCenter: RemoteCommandCenterProtocol?,
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default,
        startupWatchdogDeadline: Duration = .seconds(15),
        reachability: NetworkReachability? = nil,
        defaults: DefaultsStorage = UserDefaults.standard
    ) {
        self.player = player
        self.audioSession = audioSession
        self.remoteCommandCenter = remoteCommandCenter
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.startupWatchdogDeadline = startupWatchdogDeadline
        self.reachability = reachability
        self.defaults = defaults

        // NOTE: We intentionally do NOT call configureAudioSessionIfNeeded() here.
        // Setting the audio session category to .playback during init interrupts
        // other apps' audio. Configuration is deferred until play() is called.
        setUpRemoteCommandCenter()
        setUpNotifications()
        setUpPlayerObservation()
        setUpCPUAggregator()
        applyPersistedGain()
    }
    #else
    /// Creates a controller with injected dependencies (macOS/watchOS)
    /// - Parameters:
    ///   - player: The audio player implementation to use
    ///   - notificationCenter: Notification center for system notifications
    ///   - analytics: Analytics service for playback events
    ///   - backoffTimer: Exponential backoff timer for reconnection attempts
    public init(
        player: AudioPlayerProtocol,
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default,
        startupWatchdogDeadline: Duration = .seconds(15),
        reachability: NetworkReachability? = nil,
        defaults: DefaultsStorage = UserDefaults.standard
    ) {
        self.player = player
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.startupWatchdogDeadline = startupWatchdogDeadline
        self.reachability = reachability
        self.defaults = defaults

        setUpPlayerObservation()
        setUpCPUAggregator()
        applyPersistedGain()
    }
    #endif

    @MainActor
    deinit {
        stateObservationTask?.cancel()
        eventTask?.cancel()
        reconnectTask?.cancel()
        reachabilityMonitorTask?.cancel()
        startupWatchdogTask?.cancel()
        #if os(iOS) || os(tvOS)
        sessionActivationRetryTask?.cancel()
        #endif
        if let interruptionObservation { notificationCenter.removeObserver(interruptionObservation) }
        if let routeChangeObservation { notificationCenter.removeObserver(routeChangeObservation) }
        #if os(iOS) || os(tvOS)
        removeRemoteCommandTargets()
        #endif
    }

    // MARK: - Public Methods

    /// Toggle playback state
    /// - Parameter reason: Why playback was toggled (for analytics)
    public func toggle(reason: PlaybackReason) {
        if isPlaying {
            analytics.capture(PlaybackStoppedEvent(duration: playbackDuration))
            stop(reason: reason)
        } else {
            play(reason: reason)
        }
    }

    /// Start playback
    /// - Parameter reason: Why playback was started (for analytics)
    public func play(reason: PlaybackReason) {
        Log(.info, category: .playback, "Play requested (reason: \(reason.rawValue))")
        let context: PlaybackContext = isForegrounded ? .foreground : .background
        cpuAggregator?.startSession(context: context)

        // Cancel any pending reconnect attempt so an orphaned task can't wake
        // up later and falsely credit the user's manual play as automatic
        // recovery (see StallRecoverySabotageTests / Bug B).
        reconnectTask?.cancel()
        reconnectTask = nil
        leaveHoldingPattern()
        backoffTimer.reset()

        playbackIntended = true
        wasPlayingBeforeRouteDisconnect = false
        stallStartTime = nil
        playbackStartTime = playbackStartTime ?? Date()
        // Arm the play-intent → first-audio watchdog (#518). Placed before the
        // activation guard so it also covers the silent paths that never reach
        // `player.play()`: a `'!int'` deferral whose bounded retries exhaust
        // (the non-`'!int'` abort below doesn't wait for it — that failure is
        // known synchronously and escalates immediately). Disarmed on first
        // audio / reaching `.playing` / any error / stop.
        armStartupWatchdog()
        #if os(iOS) || os(tvOS)
        guard activateAudioSession() else {
            // A `CannotInterruptOthers` failure schedules a deferred retry and
            // keeps `playbackIntended` set so playback resumes once the
            // transient state clears (or the interruption ends). Any other
            // failure is fatal for this attempt and tears the intent down.
            if sessionActivationPending {
                Log(.info, category: .playback, "Deferring play: audio session activation retry pending")
                pendingPlaybackReason = reason
            } else {
                // Non-`'!int'` activation failure, known synchronously. Rather
                // than returning into silence (invisible, and the user still
                // wants audio) or spending the whole watchdog deadline as a
                // dead spinner, escalate recovery immediately: same
                // `silent_startup` signal (this is one of the named fully-silent
                // startup paths), same ramp→holding handoff. Intent stays set
                // and the CPU session follows it (#512) — it ends when intent
                // goes false (stop). See #518 (design 6-A).
                Log(.error, category: .playback, "Audio session activation failed; escalating silent-startup recovery immediately")
                escalateSilentStartup(description: "Audio session activation failed at play intent")
            }
            return
        }
        #endif

        startPlayerAfterActivation(reason: reason)
    }

    /// Starts the underlying player and records the play once the audio session
    /// is (or was) active. Split out from `play()` so the deferred
    /// session-activation retry can resume playback without duplicating this
    /// tail. See #514.
    private func startPlayerAfterActivation(reason: PlaybackReason) {
        // Always play fresh for live streaming (don't resume paused state)
        player.play()
        // Sync stored state immediately so isPlaying reflects the intent without
        // waiting for the async stateStream to propagate. The stateStream observation
        // will keep playerState in sync for subsequent player-driven transitions.
        playerState = player.state
        analytics.capture(PlaybackStartedEvent(reason: reason.rawValue))
        donatePlayIntent()
    }
    
    /// Calculate how long playback has been active
    private var playbackDuration: TimeInterval {
        guard let startTime = playbackStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    /// Stop playback and disconnect from stream
    /// - Parameter reason: Why playback was stopped (for analytics)
    public func stop(reason: PlaybackReason) {
        Log(.info, category: .playback, "Stop requested (reason: \(reason.rawValue))")
        cpuAggregator?.endSession(reason: .userStopped)

        reconnectTask?.cancel()
        reconnectTask = nil
        leaveHoldingPattern()
        disarmStartupWatchdog()
        backoffTimer.reset()

        playbackIntended = false
        stallStartTime = nil
        if reason != .routeDisconnected {
            wasPlayingBeforeRouteDisconnect = false
        }
        player.stop()
        playerState = player.state
        playbackStartTime = nil
        #if os(iOS) || os(tvOS)
        // Cancel any deferred session-activation retry — the user (or system)
        // no longer wants playback, so we must not keep trying to interrupt.
        clearPendingSessionActivation()
        deactivateAudioSession()
        #endif
    }

    // MARK: - Time-Shift Support

    /// Whether the current player supports time-shifting (seeking within a live stream).
    public var supportsTimeShift: Bool {
        player is TimeShiftablePlayer
    }

    /// Whether the player is currently at or near the live edge.
    public var isAtLiveEdge: Bool {
        (player as? TimeShiftablePlayer)?.isAtLiveEdge ?? true
    }

    /// Seconds behind the live edge. Returns 0 when at live or when time-shift is unsupported.
    public var secondsBehindLive: TimeInterval {
        (player as? TimeShiftablePlayer)?.secondsBehindLive ?? 0
    }

    /// Maximum seconds the listener can scrub backwards.
    public var maxLookbackSeconds: TimeInterval {
        (player as? TimeShiftablePlayer)?.maxLookbackSeconds ?? 0
    }

    /// Seek to a position expressed as seconds behind the live edge.
    public func seek(secondsBehindLive: TimeInterval) async {
        await (player as? TimeShiftablePlayer)?.seek(secondsBehindLive: secondsBehindLive)
    }

    /// Jump to the live edge.
    public func seekToLive() async {
        await (player as? TimeShiftablePlayer)?.seekToLive()
    }

    /// Stream of time position updates from the underlying player, if it supports time-shifting.
    public var timePositionStream: AsyncStream<TimeInterval>? {
        (player as? TimeShiftablePlayer)?.timePositionStream
    }

    // MARK: - Gain Boost

    /// Whether the current player supports an output gain boost (in decibels).
    /// True for the AVAudioEngine-based MP3 streamer; false for the AVPlayer-based
    /// Radio/HLS players, which have no gain stage.
    public var supportsGainBoost: Bool {
        player is GainBoostablePlayer
    }

    /// UserDefaults key for the persisted stream-gain boost.
    private static let gainDecibelsKey = "debug.streamGainDecibels"

    /// Output gain applied to the stream, in decibels. `0` is unity; the effective
    /// startup value comes from persistence, or `defaultGainDecibels` on a fresh
    /// install (see `applyPersistedGain()`). Forwarded to the player when it
    /// supports boosting; a no-op otherwise. Persisted via the injected
    /// `DefaultsStorage`. Intended for the debug menu; the player clamps to its
    /// supported range.
    public var gainDecibels: Float = 0 {
        didSet {
            (player as? GainBoostablePlayer)?.gainDecibels = gainDecibels
            defaults.set(gainDecibels, forKey: Self.gainDecibelsKey)
        }
    }

    /// Out-of-the-box boost applied when nothing has been persisted, in decibels.
    /// Every fresh install / post-Reset launch starts here; change this literal to
    /// ship a different default. `0` means no boost until the user opts in.
    static let defaultGainDecibels: Float = 4.5

    /// Restores the persisted stream gain and forwards it to the current player.
    /// Called at the end of `init`, after `player` and `defaults` are set, so a
    /// boost survives relaunch and player recreation. When nothing is persisted
    /// (fresh install), falls back to `defaultGainDecibels` and seeds it — setting
    /// via this method (not the initializer) fires `didSet`, so the value reaches
    /// the player and is written to defaults.
    private func applyPersistedGain() {
        let stored = defaults.object(forKey: Self.gainDecibelsKey) as? Float ?? Self.defaultGainDecibels
        gainDecibels = stored
    }

    // MARK: - CPU Session Aggregation

    private func setUpCPUAggregator() {
        #if !os(watchOS)
        self.cpuAggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { [weak self] in
                guard let self else { return .mp3Streamer }
                if self.player is RadioPlayer {
                    return .radioPlayer
                }
                if self.player is HLSPlayer {
                    return .hlsPlayer
                }
                return .mp3Streamer
            }
        )
        #endif
    }

    // MARK: - Audio Session (iOS/tvOS only)

    #if os(iOS) || os(tvOS)
    /// Audio session category is configured lazily on first play() to avoid
    /// interrupting other apps' audio during app launch.
    private var audioSessionConfigured = false
    
    /// Prepares the audio session for playback without actually starting playback.
    /// Call this at the start of an intent to signal to iOS that audio playback is imminent,
    /// which helps prevent the app from being suspended during stream connection.
    public func prepareForPlayback() {
        configureAudioSessionIfNeeded()
        activateAudioSession()
    }

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured, let session = audioSession else { return }
        audioSessionConfigured = true
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            Log(.info, category: .playback, "Audio session configured for playback with longFormAudio policy")
        } catch {
            Log(.error, category: .playback, "Failed to configure audio session: \(error)")
        }
    }

    /// Activates the audio session, returning whether activation succeeded.
    /// - Returns: `true` if the session was activated (or no session exists), `false` on failure.
    ///
    /// A `CannotInterruptOthers` ('!int') failure — the app can't interrupt
    /// other audio, seen in the field around foreground/background transitions
    /// and rapid play/pause (#514) — schedules a bounded deferred retry rather
    /// than giving up, so a transient state doesn't strand playback.
    @discardableResult
    private func activateAudioSession() -> Bool {
        guard let session = audioSession else { return true }
        // Configure the audio session category if not already done
        configureAudioSessionIfNeeded()
        do {
            try session.setActive(true, options: [])
            audioSessionActivated = true
            clearPendingSessionActivation()
            Log(.info, category: .playback, "Audio session activated")
            return true
        } catch {
            Log(.error, category: .playback, "Failed to activate audio session: \(error)")
            if isCannotInterruptOthers(error) {
                scheduleSessionActivationRetry()
            }
            return false
        }
    }

    /// Whether the error is a `com.apple.coreaudio.avfaudio`
    /// `CannotInterruptOthers` ('!int') failure — the transient "can't interrupt
    /// other audio" state that the deferred retry is designed to ride out.
    private func isCannotInterruptOthers(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == avfaudioErrorDomain
            && nsError.code == cannotInterruptOthersErrorCode
    }

    /// Schedules a bounded, delayed sequence of activation retries after a
    /// `CannotInterruptOthers` failure. Deliberately does NOT busy-loop: it
    /// spaces attempts out and stops after `maxSessionActivationRetries`, and an
    /// interruption-ended notification can short-circuit the wait via
    /// `reactivateAfterInterruptionIfPending()`.
    private func scheduleSessionActivationRetry() {
        // Never activate while backgrounded — foregrounding drives its own
        // reactivation path — and only when playback is still intended.
        guard playbackIntended, isForegrounded else { return }
        // A retry is already in flight; let it run to completion.
        guard !sessionActivationPending else { return }

        sessionActivationPending = true
        Log(.info, category: .playback, "Audio session activation deferred (CannotInterruptOthers); scheduling bounded retry")

        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while attempt < self.maxSessionActivationRetries {
                attempt += 1
                do {
                    try await Task.sleep(for: self.sessionActivationRetryDelay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                // Bail if playback intent was dropped or we went to background
                // while waiting.
                guard self.playbackIntended, self.isForegrounded, self.sessionActivationPending else { return }

                if self.retrySessionActivation() {
                    return
                }
            }
            // Budget exhausted without success — stop deferring so a later
            // foreground/interruption-ended event can start fresh.
            Log(.error, category: .playback, "Audio session activation retries exhausted; giving up for this attempt")
            self.sessionActivationPending = false
            self.pendingPlaybackReason = nil
            self.sessionActivationRetryTask = nil
        }
    }

    /// Attempts a single (re)activation of the session and, on success, resumes
    /// the deferred playback. Returns whether activation succeeded.
    @discardableResult
    private func retrySessionActivation() -> Bool {
        guard let session = audioSession else { return true }
        configureAudioSessionIfNeeded()
        do {
            try session.setActive(true, options: [])
            audioSessionActivated = true
            let reason = pendingPlaybackReason
            clearPendingSessionActivation()
            Log(.info, category: .playback, "Audio session activated after deferred retry")
            if let reason, playbackIntended, !isPlaying {
                startPlayerAfterActivation(reason: reason)
            }
            return true
        } catch {
            Log(.info, category: .playback, "Deferred audio session activation still blocked: \(error)")
            return false
        }
    }

    /// Called when the system posts an interruption-ended notification. If a
    /// session activation was deferred, activation is now permitted again, so
    /// attempt it immediately rather than waiting out the retry cadence — this
    /// is what "respect interruption-ended rather than busy-retrying" means.
    private func reactivateAfterInterruptionIfPending() {
        guard sessionActivationPending, playbackIntended, isForegrounded else { return }
        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = nil
        if !retrySessionActivation() {
            // Still blocked — resume the bounded retry cadence.
            sessionActivationPending = false
            scheduleSessionActivationRetry()
        }
    }

    /// Clears any deferred-activation bookkeeping and cancels the retry task.
    private func clearPendingSessionActivation() {
        sessionActivationPending = false
        pendingPlaybackReason = nil
        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = nil
    }

    private func deactivateAudioSession() {
        // Only deactivate if we previously activated - AVAudioSession has no isActive property
        guard audioSessionActivated, let session = audioSession else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActivated = false
            Log(.info, category: .playback, "Audio session deactivated")
        } catch {
            Log(.error, category: .playback, "Failed to deactivate audio session: \(error)")
        }
    }
    #endif

    // MARK: - Remote Command Center (iOS/tvOS only)

    #if os(iOS) || os(tvOS)
    private func setUpRemoteCommandCenter() {
        guard let commandCenter = remoteCommandCenter else { return }

        // Play command
        commandCenter.playCommand.isEnabled = true
        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.play(reason: .remotePlayCommand)
            }
            return .success
        }
        commandTargets.append(playTarget)

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.analytics.capture(PlaybackStoppedEvent(duration: self.playbackDuration))
                self.stop(reason: .remotePauseCommand)
            }
            return .success
        }
        commandTargets.append(pauseTarget)

        // Toggle play/pause command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.toggle(reason: .remoteToggleCommand)
            }
            return .success
        }
        commandTargets.append(toggleTarget)

        // Disable unsupported commands
        commandCenter.stopCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false

        // Enable seek commands when the player supports time-shifting
        if player is TimeShiftablePlayer {
            commandCenter.skipBackwardCommand.isEnabled = true
            commandCenter.skipBackwardCommand.preferredIntervals = [15]
            let skipBackTarget = commandCenter.skipBackwardCommand.addTarget { [weak self] event in
                guard let self,
                      let skipEvent = event as? MPSkipIntervalCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor in
                    let newOffset = self.secondsBehindLive + skipEvent.interval
                    await self.seek(secondsBehindLive: min(newOffset, self.maxLookbackSeconds))
                }
                return .success
            }
            commandTargets.append(skipBackTarget)

            commandCenter.skipForwardCommand.isEnabled = true
            commandCenter.skipForwardCommand.preferredIntervals = [15]
            let skipFwdTarget = commandCenter.skipForwardCommand.addTarget { [weak self] event in
                guard let self,
                      let skipEvent = event as? MPSkipIntervalCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor in
                    let newOffset = self.secondsBehindLive - skipEvent.interval
                    await self.seek(secondsBehindLive: max(0, newOffset))
                }
                return .success
            }
            commandTargets.append(skipFwdTarget)

            commandCenter.changePlaybackPositionCommand.isEnabled = true
            let positionTarget = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let self,
                      let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor in
                    let secondsBehind = self.maxLookbackSeconds - positionEvent.positionTime
                    await self.seek(secondsBehindLive: max(0, secondsBehind))
                }
                return .success
            }
            commandTargets.append(positionTarget)
        } else {
            commandCenter.skipForwardCommand.isEnabled = false
            commandCenter.skipBackwardCommand.isEnabled = false
            commandCenter.changePlaybackPositionCommand.isEnabled = false
        }
    }

    private func removeRemoteCommandTargets() {
        guard let commandCenter = remoteCommandCenter else { return }

        for target in commandTargets {
            commandCenter.playCommand.removeTarget(target)
            commandCenter.pauseCommand.removeTarget(target)
            commandCenter.togglePlayPauseCommand.removeTarget(target)
        }
        commandTargets.removeAll()
    }
    #endif

    // MARK: - Notifications (iOS/tvOS only)

    #if os(iOS) || os(tvOS)
    private func setUpNotifications() {
        interruptionObservation = notificationCenter.addMainActorObserver(
            for: InterruptionMessage.self
        ) { [weak self] message in
            self?.handleInterruption(message)
        }

        routeChangeObservation = notificationCenter.addMainActorObserver(
            for: RouteChangeMessage.self
        ) { [weak self] message in
            self?.handleRouteChange(message)
        }
    }
    #endif

    // MARK: - App Lifecycle (iOS only)
    // These methods should be called from SwiftUI's scenePhase handler
    // rather than using UIApplication notifications, to avoid race conditions
        
    #if os(iOS)
    /// Call this when the app enters the background (from SwiftUI scenePhase)
    /// Only deactivates the audio session if playback is NOT intended
    public func handleAppDidEnterBackground() {
        Log(.info, category: .playback, "App entered background (playbackIntended: \(playbackIntended))")
        isForegrounded = false

        // Abandon any in-flight session-activation retry. The retry loop can't
        // run while backgrounded (it bails on `isForegrounded`), and a bailed
        // loop leaves `sessionActivationPending` set — which would make the
        // foreground reactivation path early-out of `scheduleSessionActivationRetry`
        // and never reschedule, stranding playback (#514). Foregrounding
        // re-drives activation from scratch via `handleAppWillEnterForeground`.
        clearPendingSessionActivation()

        // Suspend render tap - no point running visualization in background
        if renderTapDesired {
            player.removeRenderTap()
        }

        if isPlaying {
            cpuAggregator?.transitionContext(to: .background)
        }
        guard !playbackIntended else { return }
        deactivateAudioSession()
    }

    /// Call this when the app enters the foreground (from SwiftUI scenePhase)
    /// Reactivates the audio session if playback is intended
    public func handleAppWillEnterForeground() {
        Log(.info, category: .playback, "App entering foreground (playbackIntended: \(playbackIntended))")
        isForegrounded = true

        // Restore render tap if visualization was active before backgrounding
        if renderTapDesired {
            player.installRenderTap()
        }

        if isPlaying {
            cpuAggregator?.transitionContext(to: .foreground)
        }
        if playbackIntended {
            if (playerState == .idle || playerState.isError) && reconnectTask == nil {
                // Genuinely stranded: playback is intended but the player is idle
                // or in a terminal error and no reconnect is in flight — e.g. a
                // session activation was deferred (CannotInterruptOthers) while
                // backgrounded, or the stream errored out with backoff exhausted.
                // Re-drive the full play path so activation *and* the player
                // start happen (a fresh '!int' defers with a reason so the retry
                // resumes playback rather than activating a silent session).
                // See #514.
                play(reason: .resumeAfterForeground)
            } else {
                // Either still playing (backgrounded mid-stream) or actively
                // connecting / buffering / reconnecting. Don't restart — that
                // would cancel a healthy reconnect, discard backoff progress,
                // and emit a spurious playback-start. Just re-affirm the session.
                activateAudioSession()
            }
        }
    }
    #endif

    #if os(iOS) || os(tvOS)
    private func handleInterruption(_ message: InterruptionMessage) {
        switch message.type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                analytics.capture(PlaybackStoppedEvent(reason: PlaybackReason.interruptionBegan.rawValue, duration: playbackDuration))
                stop(reason: .interruptionBegan)
            }

        case .ended:
            if message.options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                play(reason: .resumeAfterInterruption)
            } else {
                // No prior in-app interruption to resume from, but the system
                // says the interruption is over. If a session activation was
                // deferred (CannotInterruptOthers), try it now instead of
                // waiting out the retry cadence. See #514.
                reactivateAfterInterruptionIfPending()
            }
            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ message: RouteChangeMessage) {
        switch message.reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - stop playback per Apple HIG
            wasPlayingBeforeRouteDisconnect = isPlaying
            if isPlaying {
                analytics.capture(PlaybackStoppedEvent(reason: PlaybackReason.routeDisconnected.rawValue, duration: playbackDuration))
                stop(reason: .routeDisconnected)
            }

        case .newDeviceAvailable:
            // Device reconnected (e.g., AirPod reinserted) - resume if we were playing before disconnect
            if wasPlayingBeforeRouteDisconnect {
                play(reason: .resumeAfterRouteReconnect)
            }

        default:
            // AudioEnginePlayer handles restarting the engine on configuration changes
            break
        }
    }
    #endif

    // MARK: - Intent Donation

    /// Donates an INPlayMediaIntent to Siri so WXYC appears in Lock Screen suggestions.
    /// iOS learns from these donations to surface the app based on user listening patterns.
    private func donatePlayIntent() {
        #if canImport(Intents) && !os(macOS)
        let mediaItem = INMediaItem(
            identifier: RadioStation.WXYC.name,
            title: "WXYC 89.3 FM",
            type: .radioStation,
            artwork: nil
        )

        let intent = INPlayMediaIntent(
            mediaItems: [mediaItem],
            mediaContainer: nil,
            playShuffled: nil,
            resumePlayback: true,
            playbackQueueLocation: .now,
            playbackSpeed: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        Task { try? await interaction.donate() }
        #endif
    }
}

// MARK: - Convenience for views

extension AudioPlayerController {
    /// Creates a fresh stream of audio buffers for visualization.
    /// Each call returns a new stream; the previous stream's continuation is finished.
    public func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        player.makeAudioBufferStream()
    }

    #if os(iOS) || os(tvOS)
    /// The output latency of the current audio route in seconds.
    /// Updates automatically when the audio route changes (e.g., switching to AirPlay).
    public var outputLatency: TimeInterval {
        audioSession?.outputLatency ?? 0
    }
    #else
    /// Output latency is not available on macOS/watchOS.
    public var outputLatency: TimeInterval { 0 }
    #endif

    /// Install the render tap for audio visualization.
    /// The tap runs at ~60Hz and consumes CPU, so only install when actively displaying visualizations.
    /// The tap is automatically suspended when the app enters background and restored on foreground.
    public func installRenderTap() {
        renderTapDesired = true
        guard isForegrounded else {
            Log(.debug, category: .playback, "Render tap install deferred (app backgrounded)")
            return
        }
        player.installRenderTap()
    }

    /// Remove the render tap when visualization is no longer needed.
    public func removeRenderTap() {
        renderTapDesired = false
        player.removeRenderTap()
    }

    private func setUpPlayerObservation() {
        // Observe player state changes and mirror to the stored `playerState` property
        // so the Observation framework can track mutations.
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self] in
            guard let self else { return }
            for await newState in player.stateStream {
                guard !Task.isCancelled else { break }
                self.playerState = newState
                // Reaching `.playing` is the universal startup-success signal —
                // it disarms the startup watchdog for every player type,
                // including RadioPlayer/HLS which never emit `.firstAudio`. It
                // also prevents a healthy-start-then-stall from misfiring
                // `silent_startup` (a stall is the `.stall` reconnect path's
                // job, not a silent start). See #518.
                //
                // It is also the universal *recovery* signal that tears down the
                // holding pattern and its reachability monitor (#517). Routing
                // teardown through `.playing` — rather than only the holding
                // attempt's own success branch — closes the leak where a
                // mid-holding `.stall` restarts the bounded ramp, the ramp
                // succeeds, and the monitor is stranded across healthy playback.
                if newState == .playing {
                    self.disarmStartupWatchdog()
                    self.leaveHoldingPattern()
                }
            }
        }

        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in player.eventStream {
                switch event {
                case .stall:
                    handleStall()
                case .recovery:
                    handleRecovery()
                case .firstAudio(let timeToAudio):
                    handleFirstAudio(timeToAudio: timeToAudio)
                case .error(let error):
                    // The inner layer surfaced a signal, so the fully-silent
                    // hypothesis is disproven — disarm the startup watchdog so it
                    // can't stack a `silent_startup` on top of this error for the
                    // same failed start (dedup vs #487's `startup_timeout`). #518.
                    self.disarmStartupWatchdog()
                    // Capture analytics for the error
                    let playerType = self.resolvedPlayerType
                    self.analytics.capture(StreamErrorEvent(
                        playerType: playerType,
                        errorType: self.classifyError(error),
                        errorDescription: error.localizedDescription,
                        reconnectAttempts: Int(self.backoffTimer.numberOfAttempts),
                        sessionDuration: self.playbackDuration,
                        stallDuration: self.stallStartTime.map { Date().timeIntervalSince($0) },
                        recoveryMethod: .automaticReconnect
                    ))
                    // Do NOT end the CPU session on a transient error. The
                    // session follows playback INTENT, not individual errors —
                    // MP3Streamer emits `.error` on ordinary connect failures
                    // that the reconnect loop (and holding pattern) recovers
                    // from, so tearing the session down here would strand a
                    // still-intended recovery. It ends only when intent goes
                    // false (stop). See #512.
                    Log(.error, category: .playback, "Player error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleStall() {
        Log(.warning, category: .playback, "Stall detected, starting backoff recovery")
        // Only record the first stall timestamp so repeated stall events don't
        // shorten the reported stall duration.
        stallStartTime = stallStartTime ?? Date()
        analytics.capture(PlaybackStoppedEvent(reason: "stalled", duration: playbackDuration))

        // Attempt reconnection with exponential backoff
        attemptReconnectWithExponentialBackoff()
    }

    private func handleRecovery() {
        Log(.info, category: .playback, "Playback recovered from stall")
        captureRecoveryIfNeeded()
    }

    /// Captures the playback-start success signal forwarded by the player as an
    /// `AudioPlayerInternalEvent.firstAudio`. Emitting it here — the same layer
    /// that captures `StreamErrorEvent` — keeps success and failure counted
    /// together and comparable across player types (issue #513). The player is
    /// responsible for firing this once per successful start, so no de-duplication
    /// is needed here.
    private func handleFirstAudio(timeToAudio: TimeInterval) {
        // Redundant with the `.playing` state disarm (MP3Streamer emits
        // `.firstAudio` at the same moment it reaches `.playing`), but explicit
        // and idempotent — the richer MP3Streamer-specific success signal. #518.
        disarmStartupWatchdog()
        let playerType = resolvedPlayerType
        Log(.info, category: .playback, "First audio after \(String(format: "%.2f", timeToAudio))s (\(playerType.rawValue))")
        analytics.capture(PlaybackFirstAudioEvent(
            playerType: playerType,
            timeToFirstAudio: timeToAudio
        ))
    }

    // MARK: - Startup Watchdog (#518)

    /// Arms the play-intent → first-audio watchdog. Idempotent: cancels any prior
    /// arm first, so re-entrant `play()` calls collapse to a single live timer.
    /// The timer is measured from the establishing `play()` (user intent), which
    /// is the span the `silent_startup` deadline is meant to bound.
    ///
    /// `self` is held weakly across the sleep (only the deadline is captured by
    /// value) so an armed watchdog never extends the controller's lifetime.
    private func armStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { [weak self, deadline = startupWatchdogDeadline] in
            try? await Task.sleep(for: deadline)
            guard let self, !Task.isCancelled else { return }
            // Consult the live player as well as the mirrored `isPlaying`: at
            // the deadline boundary a `.playing` transition may have been
            // emitted but not yet processed by the state observer, and that
            // near-miss must not pollute the silent_startup fleet metric.
            guard self.playbackIntended, !self.isPlaying, !self.player.isPlaying else { return }
            self.handleStartupWatchdogTimeout()
        }
    }

    /// Disarms the startup watchdog. Called on every startup-success or
    /// terminal signal — reaching `.playing`, `.firstAudio`, any `.error`, and
    /// `stop()` — on the escalation handoff itself, and in `deinit`. Idempotent.
    private func disarmStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
    }

    /// The play-intent → first-audio deadline elapsed with no audio and no other
    /// signal: the fully-silent startup class (Sentry IOS-31 / IOS-35).
    private func handleStartupWatchdogTimeout() {
        Log(.error, category: .playback, "Play intent produced no audio within the startup deadline; escalating silent-startup recovery")
        escalateSilentStartup(description: "No audio or error within the play-intent→first-audio deadline")
    }

    /// Makes a silent startup visible (`silent_startup`) and self-healing by
    /// handing off to the same ramp→holding recovery a mid-stream stall uses.
    /// One-shot: the reconnect machinery owns the phase from here, so the
    /// watchdog is disarmed and does not re-arm. Reached from the watchdog
    /// deadline and, immediately, from a synchronous non-`'!int'` activation
    /// abort in `play()`.
    private func escalateSilentStartup(description: String) {
        disarmStartupWatchdog()
        analytics.capture(StreamErrorEvent(
            playerType: resolvedPlayerType,
            errorType: .silentStartup,
            errorDescription: description,
            reconnectAttempts: Int(backoffTimer.numberOfAttempts),
            sessionDuration: playbackDuration,
            stallDuration: nil,
            recoveryMethod: .automaticReconnect
        ))
        // Reuse the vetted reconnect ramp (first wait is 0.0 → immediate): it
        // re-activates the session (which may itself be the problem), re-calls
        // `player.play()`, and on continued failure stays on the ramp then falls
        // into the uncapped, intent-gated holding pattern (#512). No
        // `stallStartTime` is set — there was no stall, so
        // `captureRecoveryIfNeeded` correctly stays quiet and eventual success
        // is signalled by `.firstAudio`.
        attemptReconnectWithExponentialBackoff()
    }

    private func attemptReconnectWithExponentialBackoff() {
        guard let waitTime = self.backoffTimer.nextWaitTime() else {
            // The bounded exponential ramp is spent. Emit the terminal-ramp
            // signal ONCE at the boundary (metric continuity with the 32-user
            // `backoff_exhausted` v3.1 baseline) — the ramp→hold split means no
            // per-cycle re-entry, so no dedup flag is needed.
            let playerType = self.resolvedPlayerType
            let stallDuration = stallStartTime.map { Date().timeIntervalSince($0) }
            analytics.capture(StreamErrorEvent(
                playerType: playerType,
                errorType: .backoffExhausted,
                errorDescription: "Maximum reconnection attempts (\(backoffTimer.maximumAttempts)) exhausted",
                reconnectAttempts: Int(backoffTimer.numberOfAttempts),
                sessionDuration: playbackDuration,
                stallDuration: stallDuration,
                recoveryMethod: .retryWithBackoff
            ))
            // Do NOT end the CPU session here: it follows playback INTENT, not a
            // transient error, so a later holding-pattern recovery credits the
            // same session. Rather than returning into permanent silence, hand
            // off to a flat, uncapped holding pattern that keeps retrying while
            // playback is still intended. See #512.
            Log(.warning, category: .playback, "Backoff ramp exhausted after \(self.backoffTimer.numberOfAttempts) attempts; entering flat reconnect holding pattern")
            self.backoffTimer.reset()
            self.enterReconnectHoldingPattern()
            return
        }

        let attemptNumber = backoffTimer.numberOfAttempts
        Log(.info, category: .playback, "Reconnect attempt \(attemptNumber)/\(backoffTimer.maximumAttempts), waiting \(String(format: "%.1f", waitTime))s")

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            if self.player.isPlaying {
                Log(.info, category: .playback, "Already playing, cancelling reconnect")
                self.captureRecoveryIfNeeded()
                self.backoffTimer.reset()
                return
            }

            do {
                try await Task.sleep(for: .seconds(waitTime))
                guard !Task.isCancelled else { return }

                #if os(iOS) || os(tvOS)
                guard self.activateAudioSession() else {
                    // Activation failure is a failed attempt, not a terminal
                    // condition: stay on the ramp (mirroring the holding
                    // pattern) so a persistent failure escalates to
                    // backoff_exhausted → holding rather than stranding a
                    // still-intended playback in silence. See #518.
                    Log(.error, category: .playback, "Reconnect attempt blocked: audio session activation failed; continuing ramp")
                    self.attemptReconnectWithExponentialBackoff()
                    return
                }
                #endif
                self.player.play()

                // Wait for the player to reach a terminal state (playing or
                // error) rather than declaring victory at a fixed 500 ms grace
                // check. The cold-connect path (HTTP connect + buffer fill)
                // observed in the field takes ~1.3–1.4 s; a fixed 500 ms grace
                // always saw `isPlaying == false`, immediately triggered the
                // next retry, and tore down the in-flight connection.
                // See `StallRecoverySabotageTests` / Bug A.
                let reachedPlaying = await self.waitForPlayingOrError(timeout: .seconds(3))
                guard !Task.isCancelled else { return }

                if !reachedPlaying {
                    self.attemptReconnectWithExponentialBackoff()
                } else if let stallStart = self.stallStartTime {
                    // Only credit auto-recovery when `stallStartTime` is still
                    // set at the moment of the check. If something else (a
                    // user `play()`, an external play command) cleared it,
                    // we didn't actually recover anything — the audio is
                    // playing for some other reason. See Bug C in
                    // `StallRecoverySabotageTests`.
                    let totalStallTime = Date().timeIntervalSince(stallStart)
                    Log(.info, category: .playback, "Recovery successful after \(String(format: "%.1f", totalStallTime))s")
                    captureRecoveryIfNeeded()
                    self.backoffTimer.reset()
                } else {
                    // Player is playing but the stall was already resolved by
                    // someone else; just clear backoff state quietly.
                    self.backoffTimer.reset()
                }
            } catch {
                self.backoffTimer.reset()
            }
        }
    }

    /// Once the bounded exponential ramp is spent, keep trying to reconnect for
    /// as long as playback is still intended, rather than hard-giving-up into
    /// silence. A mid-stream underrun that outlives the ramp is almost always a
    /// transient network condition, and the listener still wants audio.
    ///
    /// #517 upgrades #512's *blind* flat-cadence loop with a reachability gate:
    /// while the network path is unsatisfied the loop idles (no timer wakeups,
    /// no session-activation churn), and a `→ satisfied` edge fires a pending
    /// attempt promptly instead of waiting out the cadence. The flat cadence
    /// (`maximumWaitTime`, 10s by default) is demoted to a *fallback* for the
    /// "path satisfied but the connect still fails" case (captive portal, DNS,
    /// origin down) — reachability is a gate and an accelerator, not a
    /// guarantee. When no reachability is injected the gate is inert and the
    /// original blind cadence is preserved exactly (see `reachabilityGateAllowsAttempt`).
    ///
    /// Reachability is gated at this single owner — the controller's uncapped
    /// loop. The bounded ramp above is left un-gated (it self-terminates
    /// quickly), and `MP3Streamer.attemptReconnect()` is deliberately NOT gated:
    /// each holding-pattern tick calls `player.play()`, which already drives the
    /// streamer's own bounded connect, so gating there too would fan out
    /// overlapping connects on the same `→ satisfied` edge.
    ///
    /// The retry deliberately survives backgrounding: locked-screen playback is
    /// the core radio use case, and iOS suspends the app once it stops producing
    /// audio, which throttles the background case naturally. The CPU-usage
    /// session is left open — it ends with intent (stop / play-abort), not with
    /// a transient error — so a later recovery still credits the same session.
    ///
    /// Monitor lifecycle: *pending-scoped*. Monitoring starts here and is torn
    /// down by `leaveHoldingPattern()` on recovery / stop / manual play. The
    /// tradeoff vs. a controller-lifetime monitor: no always-on cost while
    /// playback is healthy (the common case), at the price of a tiny per-entry
    /// `NWPathMonitor` setup. Holding-pattern entries are rare (only after ramp
    /// exhaustion), so the balance favours pending-scoped.
    ///
    /// Motivated by the 32-user `backoff_exhausted` field signal (v3.1).
    private func enterReconnectHoldingPattern() {
        let holdInterval = backoffTimer.maximumWaitTime
        Log(.warning, category: .playback, "Reconnect holding pattern engaged: reachability-gated, flat \(String(format: "%.1f", holdInterval))s fallback cadence while playback is intended")
        holdingPatternEngaged = true
        beginReachabilityMonitoring()
        scheduleHoldingReconnect(after: holdInterval, trigger: .holdingFallback)
    }

    /// Schedules the holding pattern's timed *fallback* attempt after
    /// `holdInterval`. On wake it defers to `performHoldingReconnectAttempt()` —
    /// the single funnel every holding attempt (timed or reachability-triggered)
    /// passes through — so the in-flight guard coalesces them. Never exhausts.
    ///
    /// `trigger` records why this attempt is being scheduled so a successful
    /// recovery is attributed correctly (`.holdingFallback` for the timed
    /// cadence, `.reachabilityResume` for a `→ satisfied` edge). See #517.
    private func scheduleHoldingReconnect(after holdInterval: TimeInterval, trigger: RecoveryMethod) {
        holdingReconnectTrigger = trigger
        reconnectTask = Task { [weak self] in
            guard let self else { return }

            // Intent dropped (stop / play-abort) — close the CPU session and
            // leave the holding pattern. `endSession` is idempotent, so the
            // primary teardown in `stop()`/`play()` already covered the common
            // case; this is the belt-and-braces intent guard.
            guard self.playbackIntended else {
                self.cpuAggregator?.endSession(reason: .userStopped)
                self.leaveHoldingPattern()
                return
            }

            if self.player.isPlaying {
                Log(.info, category: .playback, "Already playing, leaving reconnect holding pattern")
                self.captureRecoveryIfNeeded(method: self.holdingReconnectTrigger)
                self.backoffTimer.reset()
                self.leaveHoldingPattern()
                return
            }

            do {
                try await Task.sleep(for: .seconds(holdInterval))
                guard !Task.isCancelled else { return }
                guard self.playbackIntended else {
                    self.cpuAggregator?.endSession(reason: .userStopped)
                    self.leaveHoldingPattern()
                    return
                }
                await self.performHoldingReconnectAttempt()
            } catch {
                // Sleep interrupted (cancellation); intent-driven teardown owns
                // ending the session, so just clear backoff state.
                self.backoffTimer.reset()
            }
        }
    }

    /// The single funnel for a holding-pattern connect attempt, reached from the
    /// timed fallback and from the `→ satisfied` reachability edge. Idempotent
    /// under concurrency: the `holdingReconnectInFlight` guard coalesces a
    /// flapping edge (or an edge racing the timer) into the one attempt already
    /// running, so a burst of transitions can never launch overlapping connects.
    private func performHoldingReconnectAttempt() async {
        // The holding pattern may have been left out from under a still-sleeping
        // fallback timer: `leaveHoldingPattern()` (fired by the universal
        // `.playing` recovery signal / stop / manual play) disengages the pattern
        // but does not cancel `reconnectTask`, so a stranded timer can still wake
        // here. With reachability injected the gate below already blocks it (the
        // cache was reset to `nil`), but on the blind (nil-reachability) path the
        // gate is inert — so guard the engaged flag directly to keep a stray
        // attempt from firing a session activation + `player.play()` against
        // healthy playback.
        guard holdingPatternEngaged else { return }

        // Coalesce: never run two overlapping connects.
        guard !holdingReconnectInFlight else { return }

        // Reachability gate: if the path is known-unsatisfied, idle instead of
        // burning a session activation + connect that cannot succeed. Do NOT
        // reschedule a timer here — the `→ satisfied` edge is what resumes us,
        // so an unsatisfied network produces no wakeups at all. (When no
        // reachability is injected the gate is inert; see
        // `reachabilityGateAllowsAttempt`.)
        guard reachabilityGateAllowsAttempt else {
            Log(.info, category: .playback, "Holding-pattern reconnect idle: network path unsatisfied; awaiting reachability")
            return
        }

        holdingReconnectInFlight = true

        // Snapshot the attribution *now*: the `.playing` state observer runs
        // `leaveHoldingPattern()` (which resets the trigger) during the await
        // below, so reading it after the await would lose the credit. See #517.
        let attemptTrigger = holdingReconnectTrigger

        #if os(iOS) || os(tvOS)
        guard activateAudioSession() else {
            holdingReconnectInFlight = false
            Log(.error, category: .playback, "Holding-pattern reconnect aborted: audio session activation failed; will retry")
            rescheduleHoldingFallbackIfSatisfied()
            return
        }
        #endif
        player.play()

        let reachedPlaying = await waitForPlayingOrError(timeout: .seconds(3))
        holdingReconnectInFlight = false
        guard !Task.isCancelled else { return }

        if !reachedPlaying {
            // Still not connected. Keep the timed fallback going while the path
            // looks usable; if it went unsatisfied mid-attempt, suspend and
            // wait for the `→ satisfied` edge.
            rescheduleHoldingFallbackIfSatisfied()
        } else if let stallStart = stallStartTime {
            let totalStallTime = Date().timeIntervalSince(stallStart)
            Log(.info, category: .playback, "Recovery successful after \(String(format: "%.1f", totalStallTime))s (holding pattern, \(attemptTrigger.rawValue))")
            captureRecoveryIfNeeded(method: attemptTrigger)
            backoffTimer.reset()
            leaveHoldingPattern()
        } else {
            // Playing again, but the stall was already resolved by someone else;
            // just clear backoff state quietly.
            backoffTimer.reset()
            leaveHoldingPattern()
        }
    }

    /// Re-arms the timed fallback only while the path looks usable (or no
    /// reachability signal is wired — the preserved blind cadence). When the
    /// path is down we suspend the timer entirely; the `→ satisfied` edge
    /// resumes the loop, so a dead network yields no blind ticking.
    private func rescheduleHoldingFallbackIfSatisfied() {
        guard holdingPatternEngaged, playbackIntended else { return }
        if reachabilityGateAllowsAttempt {
            scheduleHoldingReconnect(after: backoffTimer.maximumWaitTime, trigger: .holdingFallback)
        } else {
            Log(.info, category: .playback, "Holding-pattern fallback suspended: awaiting network path return")
        }
    }

    /// Whether a holding-pattern attempt may proceed. With no reachability
    /// injected the loop keeps its original blind cadence (always allowed). With
    /// a signal, an attempt requires an explicit `.satisfied` — a `nil` (no
    /// signal yet) or `.unsatisfied` path idles, so a stale-optimistic seed can
    /// never fire a blind attempt on a known-down network.
    ///
    /// This idle-on-`nil` behaviour depends on the `NetworkReachability`
    /// contract that an implementation delivers the *current* path status
    /// promptly on subscription (`NWPathMonitor` does; the mock does). A
    /// hypothetical impl that only reported on *change* could leave a
    /// genuinely-satisfied path stuck at `nil` and never attempt — hence the
    /// contract is spelled out on the protocol. `nil` is otherwise transient
    /// (a few ms after `NWPathMonitor.start`).
    private var reachabilityGateAllowsAttempt: Bool {
        guard reachability != nil else { return true }
        return lastReachabilitySatisfied == true
    }

    /// Subscribes to the injected reachability signal for the duration of the
    /// holding pattern (pending-scoped). Idempotent — a live subscription is
    /// reused. No-op when no reachability is injected. The `Task` inherits this
    /// `@MainActor` context, so `handleReachabilityUpdate` runs isolated.
    private func beginReachabilityMonitoring() {
        guard let reachability, reachabilityMonitorTask == nil else { return }
        reachabilityMonitorTask = Task { [weak self] in
            for await satisfied in reachability.pathUpdates() {
                guard let self, !Task.isCancelled else { break }
                self.handleReachabilityUpdate(satisfied: satisfied)
            }
        }
    }

    /// Processes one reachability update: caches the state and, on a
    /// `→ satisfied` edge, accelerates a pending holding-pattern reconnect.
    private func handleReachabilityUpdate(satisfied: Bool) {
        let previous = lastReachabilitySatisfied
        lastReachabilitySatisfied = satisfied
        guard holdingPatternEngaged else { return }
        // Fire on the rising edge only: previous was not-satisfied (unsatisfied
        // or the initial `nil`), now satisfied. Redundant satisfied→satisfied
        // updates are ignored, so a stable healthy path never re-triggers.
        //
        // Attribution (#517): credit `.reachabilityResume` only for a *genuine*
        // observed outage-and-return (`previous == false`) — that is the case
        // where the network coming back is what drove recovery. The initial
        // delivery on an already-satisfied path (`previous == nil`) still fires
        // the edge — the loop must resume promptly rather than risk idling if
        // the timer raced ahead of the first delivery — but it is attributed to
        // the timed fallback, since reachability didn't actually change: the
        // common "origin hiccup on a stable network" case must not be mislabeled
        // a reachability resume.
        if satisfied && previous != true {
            let trigger: RecoveryMethod = (previous == false) ? .reachabilityResume : .holdingFallback
            Log(.info, category: .playback, "Network path satisfied; accelerating pending holding-pattern reconnect (\(trigger.rawValue))")
            triggerHoldingReconnectOnSatisfiedEdge(trigger: trigger)
        }
        // An `→ unsatisfied` edge needs no active work: any in-flight attempt
        // fails and returns to idle via `rescheduleHoldingFallbackIfSatisfied`,
        // and the next timed wake (if any) idles at the gate.
    }

    /// Fires a holding-pattern attempt on the `→ satisfied` edge, coalesced:
    /// only when the holding pattern is engaged and no attempt is already in
    /// flight. Cancels any sleeping fallback timer first so the edge supersedes
    /// it (prompt resume) rather than stacking a second attempt behind it.
    /// `trigger` is the attribution the resulting recovery is credited with.
    private func triggerHoldingReconnectOnSatisfiedEdge(trigger: RecoveryMethod) {
        guard holdingPatternEngaged, !holdingReconnectInFlight else { return }
        reconnectTask?.cancel()
        scheduleHoldingReconnect(after: 0, trigger: trigger)
    }

    /// Leaves the uncapped holding phase and tears down its reachability monitor
    /// (pending-scoped lifecycle). Idempotent. Called on recovery, stop, and
    /// manual play.
    private func leaveHoldingPattern() {
        holdingPatternEngaged = false
        holdingReconnectInFlight = false
        holdingReconnectTrigger = .holdingFallback
        reachabilityMonitorTask?.cancel()
        reachabilityMonitorTask = nil
        lastReachabilitySatisfied = nil
    }

    /// Polls the player's state until it reaches `.playing` (success) or
    /// `.error` (terminal failure), or the timeout elapses. Returns `true`
    /// only if the player reached `.playing` within the budget.
    ///
    /// Used by the reconnect loop instead of a fixed-duration grace sleep,
    /// because cold-connect latency in the wild can exceed any short fixed
    /// grace. The polling cadence is short enough that the wait resolves
    /// promptly once the state transitions.
    private func waitForPlayingOrError(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return false }
            let state = player.state
            if state == .playing { return true }
            if state.isError { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return player.state == .playing
    }

    /// Credits a successful stall/outage recovery, once per stall episode
    /// (guarded on `stallStartTime`).
    ///
    /// `method`, when supplied, attributes the recovery to a specific path —
    /// the holding-pattern sites pass `.reachabilityResume` / `.holdingFallback`
    /// (#517) so the two reconnect mechanisms are distinguishable in telemetry.
    /// When omitted (the mid-stream buffer-recovery and bounded-ramp sites) the
    /// method is derived from whether the exponential ramp ran.
    private func captureRecoveryIfNeeded(method: RecoveryMethod? = nil) {
        guard let stallStart = self.stallStartTime else { return }
        let playerType = self.resolvedPlayerType
        let recoveryMethod = method ?? (backoffTimer.numberOfAttempts > 0 ? .retryWithBackoff : .automaticReconnect)
        analytics.capture(StallRecoveryEvent(
            playerType: playerType,
            successful: true,
            attempts: Int(self.backoffTimer.numberOfAttempts),
            stallDuration: Date().timeIntervalSince(stallStart),
            reason: .bufferUnderrun,
            recoveryMethod: recoveryMethod
        ))
        self.stallStartTime = nil
    }

    /// Classifies an error into a StreamErrorType for analytics
    private var resolvedPlayerType: PlayerControllerType {
        if player is RadioPlayer { return .radioPlayer }
        #if !os(watchOS)
        if player is HLSPlayer { return .hlsPlayer }
        #endif
        return .mp3Streamer
    }

    private func classifyError(_ error: Error) -> StreamErrorType {
        // Check custom Swift error types first: `error as NSError` below always
        // succeeds via bridging, so the domain checks would otherwise get first crack.
        if error is StreamStartupError {
            return .startupTimeout
        }

        let nsError = error as NSError

        // Check for URL/network errors
        if nsError.domain == NSURLErrorDomain {
            return .networkError
        }

        // Check for AVFoundation errors
        if nsError.domain == AVFoundationErrorDomain {
            switch nsError.code {
            case AVError.decoderNotFound.rawValue,
                 AVError.decoderTemporarilyUnavailable.rawValue,
                 AVError.failedToParse.rawValue:
                return .decodingError
            default:
                return .playerError
            }
        }

        // Check for CoreMedia errors (often decoding-related)
        if nsError.domain == "CoreMediaErrorDomain" {
            return .decodingError
        }

        // Check for CoreAudio / AVAudioEngine / AVAudioSession errors. Without
        // this branch every real engine/session failure fell through to
        // `.unknown`, hiding it in telemetry (see #509 / #514). `'!int'`
        // (CannotInterruptOthers) is a distinct session (re)activation failure
        // and gets its own label; any other avfaudio code is a player-level
        // error rather than truly unknown.
        if nsError.domain == avfaudioErrorDomain {
            if nsError.code == cannotInterruptOthersErrorCode {
                return .sessionActivationConflict
            }
            return .playerError
        }

        return .unknown
    }

    /// The `com.apple.coreaudio.avfaudio` NSError domain used by AVAudioEngine /
    /// AVAudioSession failures.
    private var avfaudioErrorDomain: String { "com.apple.coreaudio.avfaudio" }

    /// FourCC `'!int'` (560557684) = `AVAudioSessionErrorCodeCannotInterruptOthers`:
    /// the session could not be activated because another app's audio could not
    /// be interrupted.
    private var cannotInterruptOthersErrorCode: Int {
        #if os(iOS) || os(tvOS) || os(watchOS)
        Int(AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue)
        #else
        560557684
        #endif
    }
}

// MARK: - PlaybackController Conformance

extension AudioPlayerController: PlaybackController {

    public var state: PlaybackState {
        // If there's a stall in progress, return stalled
        if stallStartTime != nil {
            return .stalled
        }

        // Convert PlayerState to PlaybackState
        // Uses the stored playerState (updated via stateStream observation)
        // rather than player.state directly, so Observation can track changes.
        return playerState.asPlaybackState
    }
}
