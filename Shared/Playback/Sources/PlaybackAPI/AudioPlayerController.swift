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
import os
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
        reachability: NWPathMonitorReachability(),
        backgroundTasks: SystemBackgroundTaskAssertion()
    )
    #elseif os(watchOS)
    public static let shared = AudioPlayerController(
        // The wrapped RadioPlayer's own analytics sink is explicitly nil —
        // this controller is the sole emitter of playback analytics. See
        // `makePlayer(for:)` below and #669.
        player: RadioPlayer(analytics: nil),
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
    /// Builds the underlying player for the given experiment arm. Every arm is
    /// constructed with its own analytics sink explicitly nil — this
    /// controller (the caller) is the sole emitter of playback analytics.
    /// MP3Streamer already defaulted its sink to nil; RadioPlayer and
    /// HLSPlayer previously defaulted to the real, shared analytics service,
    /// which double-counted every "play" alongside this controller's own
    /// capture. See #669.
    static func makePlayer(for type: PlayerControllerType) -> any AudioPlayerProtocol {
        switch type {
        case .mp3Streamer:
            MP3Streamer(configuration: MP3StreamerConfiguration(url: RadioStation.WXYC.streamURL))
        case .radioPlayer:
            RadioPlayer(analytics: nil)
        case .hlsPlayer:
            HLSPlayer(url: HLSEnvironment.loadActive().url, analytics: nil)
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
    /// too long to start" — see #251. This is `debugState`'s rendering; tests
    /// that *branch* on a field should read `debugState` directly rather than
    /// substring-match here.
    public var debugStateSnapshot: String {
        debugState.description
    }

    /// Typed counterpart to `debugStateSnapshot`. Still one accessor returning
    /// one value — not per-field visibility relaxation on the controller — but
    /// a test can wait on `debugState.sessionDeactivationInFlight` instead of
    /// matching a substring of the rendered snapshot, where a renamed field
    /// turns every waiting caller into "run out the timeout, then pass
    /// vacuously".
    public var debugState: DebugState {
        DebugState(
            playerState: playerState,
            playbackIntended: playbackIntended,
            isPlaying: isPlaying,
            isLoading: isLoading,
            audioSessionActivated: audioSessionActivated,
            sessionDeactivationInFlight: sessionDeactivationInFlight,
            isForegrounded: isForegrounded,
            holdingPatternEngaged: holdingPatternEngaged,
            holdingReconnectInFlight: holdingReconnectInFlight,
            reachabilitySatisfied: lastReachabilitySatisfied,
            holdingReconnectTrigger: holdingReconnectTrigger,
            liveHandbackAssertions: liveHandbackAssertionCount
        )
    }

    /// Background-execution assertions the deferred handback still holds. A
    /// non-zero count that never falls back to zero is a pending termination, so
    /// it belongs in the snapshot a test timeout or a field report prints.
    /// Platform-branched here rather than at the `DebugState` field so the
    /// struct itself stays free of `#if`.
    private var liveHandbackAssertionCount: Int {
        #if os(iOS) || os(tvOS)
        liveHandbackAssertions.count
        #else
        0
        #endif
    }

    /// A point-in-time capture of the controller's diagnostic state, one field
    /// per machine flag. `description` renders the single-line `key=value` form
    /// `debugStateSnapshot` has always produced, so log output is unchanged.
    public struct DebugState: CustomStringConvertible, Sendable {
        public let playerState: PlayerState
        public let playbackIntended: Bool
        public let isPlaying: Bool
        public let isLoading: Bool
        public let audioSessionActivated: Bool
        public let sessionDeactivationInFlight: Bool
        public let isForegrounded: Bool
        public let holdingPatternEngaged: Bool
        public let holdingReconnectInFlight: Bool
        public let reachabilitySatisfied: Bool?
        public let holdingReconnectTrigger: RecoveryMethod
        /// Background-execution assertions the deferred handback still holds.
        /// Always zero off iOS/tvOS, where there are no such assertions.
        public let liveHandbackAssertions: Int

        public var description: String {
            [
                "playerState=\(playerState)",
                "playbackIntended=\(playbackIntended)",
                "isPlaying=\(isPlaying)",
                "isLoading=\(isLoading)",
                "audioSessionActivated=\(audioSessionActivated)",
                "sessionDeactivationInFlight=\(sessionDeactivationInFlight)",
                "isForegrounded=\(isForegrounded)",
                "holdingPatternEngaged=\(holdingPatternEngaged)",
                "holdingReconnectInFlight=\(holdingReconnectInFlight)",
                "reachabilitySatisfied=\(reachabilitySatisfied.map(String.init(describing:)) ?? "nil")",
                "holdingReconnectTrigger=\(holdingReconnectTrigger.rawValue)",
                "liveHandbackAssertions=\(liveHandbackAssertions)",
            ].joined(separator: ", ")
        }
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
    /// Source of background-execution assertions for the deferred handback. Not
    /// `nonisolated(unsafe)` like its neighbours: assertions are begun and ended
    /// only from the main actor, never from the executor the handback itself
    /// runs on.
    @ObservationIgnored private let backgroundTasks: (any BackgroundTaskAssertionProtocol)?
    #endif

    // MARK: - State

    /// Whether playback was active immediately before the last route
    /// disconnect (e.g. headphones unplugged), so a later reconnect knows
    /// whether to resume. `wasPlayingBeforeInterruption` has no equivalent
    /// field here — it moved entirely into `PlaybackInterruptionRouteHandler`
    /// (#756), since neither controller read it outside interruption
    /// handling. This flag stays controller-owned because `play()` and
    /// `PlaybackStopTeardown` also touch it.
    private var wasPlayingBeforeRouteDisconnect = false
    /// Tracks if we intend to be playing (survives transient state changes)
    private var playbackIntended = false
    /// Whether a deferred deactivation is currently in flight. `audioSessionActivated`
    /// can't serve this role: it stays set until the handback is confirmed, so a
    /// second `stop()` (or a background transition) would otherwise stack a
    /// redundant XPC call behind the first. Declared alongside
    /// `audioSessionActivated` rather than with the rest of the iOS-only session
    /// state so `debugStateSnapshot` can report it without a platform branch.
    private var sessionDeactivationInFlight = false
    /// Whether the audio session is activated, so we never try to deactivate one
    /// that was never activated. Tracks confirmed state, not intent: it is cleared
    /// only once a deferred deactivation reports the handback actually happened,
    /// so a failed one leaves it set and the next attempt retries.
    private var audioSessionActivated = false
    /// Tracks when playback started for analytics duration reporting. Backed
    /// by the monotonic `Core.Timer` (`ContinuousClock`), not a wall-clock
    /// `Date`, so an NTP step / DST change / manual clock adjustment mid-listen
    /// can't corrupt the reported `pause.duration` — and so this matches
    /// `RadioPlayerController`'s `playbackTimer`, which already used the
    /// monotonic clock. See #667.
    private var playbackTimer: Core.Timer?
    private var stallStartTime: Date?
    /// Stable per-listen identifier (#665), generated at the play intent
    /// alongside `playbackTimer` and threaded onto every playback
    /// analytics event so one continuous listen can be reconstructed from
    /// the event stream. Cleared in `stop()` — except for the interruption
    /// and route-disconnect reasons, which stop playback only as a prelude
    /// to an imminent auto-resume and must preserve the id (see `stop(reason:)`).
    private var sessionID: String?
    /// Cadence at which `playback_heartbeat` fires while playing (#666), so
    /// listening-hours and a killed/never-paused session's duration can be
    /// reconstructed from `max(cumulative_seconds)` per `session_id` without
    /// requiring a `pause`. 60s: coarse enough to be negligible next to the
    /// existing 5s CPU-sample cadence and any reasonable network budget —
    /// this rides the same active background-audio session that already
    /// keeps the app alive indefinitely while playing (unlike the widget's
    /// 40-70/day background-refresh budget, which this does not touch; see
    /// docs/configuration.md) — while still granular enough that a killed
    /// session's last heartbeat under-reports its true duration by at most a
    /// minute. Injectable so tests can use a short interval and observe
    /// several ticks quickly.
    private let heartbeatInterval: Duration
    /// Owns the `playback_heartbeat` cancel-then-loop-sleep-emit task shape
    /// (#666), extracted into `PlaybackCore` so both this controller and
    /// `RadioPlayerController` compose the same implementation instead of
    /// each maintaining a byte-identical copy (#755). Populated by
    /// `setUpHeartbeat()`, called at the end of `init` — its `onTick`
    /// closure captures `self` weakly, which Swift only permits once every
    /// other stored property has a value (mirrors `setUpCPUAggregator()`).
    @ObservationIgnored private var heartbeat: PlaybackHeartbeat?
    #if os(iOS) || os(tvOS)
    /// Owns the interruption/route-change notification subscription, the
    /// case switch, and the shared `PlaybackStoppedEvent` capture (#756),
    /// extracted into `PlaybackCore` so both this controller and
    /// `RadioPlayerController` compose the same implementation instead of
    /// each maintaining a duplicated copy. Populated by `setUpNotifications()`.
    @ObservationIgnored private var interruptionRouteHandler: PlaybackInterruptionRouteHandler?
    #endif
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
    /// The sleep behind `startupWatchdogDeadline`. Defaults to the real wall
    /// clock; tests substitute a gate so the deadline is driven by an explicit
    /// signal instead of racing scheduler latency against the async
    /// `.connectivityWaitChanged` propagation `isPlayerWaitingForConnectivity`
    /// depends on. See issue #787 (the same pattern `MP3Streamer`'s own startup
    /// watchdog uses for its inner deadline).
    private let startupWatchdogSleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var startupWatchdogTask: Task<Void, Never>?
    /// Mirrors the player's connectivity-wait state, driven by the streamer's
    /// `.connectivityWaitChanged` edges (#699). While `true`, the startup
    /// watchdog defers instead of escalating a `silent_startup`: the task is
    /// legitimately parked offline (#697), not silently starved, and escalating
    /// would restart the parked streamer one layer up and defeat the gate.
    /// `internal`, not part of the public API — exposed so tests (`@testable
    /// import`) can wait deterministically for the mirror to update rather than
    /// guessing how many scheduler turns propagation needs. See issue #787.
    @ObservationIgnored internal private(set) var isPlayerWaitingForConnectivity = false

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
    /// Delay between deferred activation retries. Injected so a test can run
    /// the whole bounded budget out in a fraction of a second.
    private let sessionActivationRetryDelay: Duration

    /// Whether a handback was asked for while one was already in flight. The
    /// request can't be served immediately and must not be dropped: the in-flight
    /// one may decline as stale. Consumed once, by
    /// `drainRequestedSessionDeactivation()`.
    private var sessionDeactivationRequested = false
    /// Background-execution assertions this controller holds and has not yet
    /// released. Tracked so each is ended exactly once — `UIApplication` treats
    /// a double-end as a programming error, and an expiration handler racing the
    /// handback's own continuation is precisely how that happens. A set rather
    /// than a single identifier because a handback that re-drives a recorded
    /// request briefly holds two: the new one is taken before the old is
    /// released, so the app is never momentarily unprotected in between.
    @ObservationIgnored private var liveHandbackAssertions: Set<BackgroundTaskID> = []

    /// Whether the system has told us our background time is spent.
    ///
    /// Latched by the expiration handler so a handback that re-drives *after*
    /// expiry doesn't arm a fresh assertion against a budget we already know is
    /// gone. `beginBackgroundTask` would still hand one out there, with a
    /// near-zero deadline — and if its handler isn't delivered before the
    /// process is suspended, that assertion is live and unended, which is the
    /// one failure the OS punishes with termination rather than a warning.
    /// Arming it would also be the same "issue more work on a spent budget" the
    /// expiration handler deliberately refuses to do directly.
    ///
    /// Cleared by `activate(_:)`: a session we just activated means audio is
    /// running again, so the next pause gets a fresh background budget.
    @ObservationIgnored private var handbackAssertionsExpired = false

    /// Serializes every `setActive` call on the session.
    ///
    /// The deferred deactivation runs off the main actor, so it can otherwise
    /// interleave with a `play()` that happened while it was in flight — pause
    /// immediately followed by play would tear down the session `play()` had
    /// just activated, and the stream would go silent. Holding this across each
    /// `setActive` makes the two mutually exclusive.
    @ObservationIgnored private let sessionLock = OSAllocatedUnfairLock()

    /// Number of successful activations so far. A deferred deactivation carries
    /// the value it was scheduled against, so one that lost the race to `play()`
    /// can recognise itself as stale.
    ///
    /// Written only from `activate(_:)`, which is main-actor isolated — so the
    /// main actor is the sole writer and may read it unlocked. `sessionLock`
    /// exists for the deactivation, which reads it from off the actor, and whose
    /// acquire pairs with the release on the writer's unlock.
    ///
    /// Same bump-capture-compare idiom as `PlaylistService`'s
    /// `liveUpdatesGeneration`; a third site should hoist a shared helper into
    /// Core rather than fork the pattern again.
    @ObservationIgnored private nonisolated(unsafe) var sessionActivationGeneration = 0
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
    ///   - sessionActivationRetryDelay: Spacing of the bounded `'!int'`
    ///     activation retries (#514). Production keeps the default; tests
    ///     shrink it to exhaust the budget quickly.
    ///   - backgroundTasks: Source of background-execution assertions, so a
    ///     deferred audio-session handback survives the app being backgrounded.
    ///     Defaults to nil — no assertion, which is what every construction site
    ///     except `shared` wants, since only a real app is ever suspended.
    ///   - startupWatchdogSleep: The sleep behind `startupWatchdogDeadline`
    ///     (#787). Production keeps the real wall clock; tests substitute a
    ///     gate so the watchdog fires on an explicit signal instead of racing
    ///     scheduler latency against `isPlayerWaitingForConnectivity`'s
    ///     propagation. Must not capture the controller: an armed watchdog holds
    ///     this closure strongly for the whole deadline, so a closure that
    ///     retained `self` would keep the controller — audio session,
    ///     remote-command targets, notification observations — alive past
    ///     teardown, defeating the `[weak self]` capture in `armStartupWatchdog()`.
    ///     Must throw only on cancellation; any other error is treated as a
    ///     failed sleep and suppresses the escalation rather than triggering it.
    public init(
        player: AudioPlayerProtocol,
        audioSession: AudioSessionProtocol?,
        remoteCommandCenter: RemoteCommandCenterProtocol?,
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default,
        startupWatchdogDeadline: Duration = .seconds(15),
        reachability: NetworkReachability? = nil,
        defaults: DefaultsStorage = UserDefaults.standard,
        heartbeatInterval: Duration = .seconds(60),
        sessionActivationRetryDelay: Duration = .milliseconds(250),
        backgroundTasks: (any BackgroundTaskAssertionProtocol)? = nil,
        startupWatchdogSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.player = player
        self.audioSession = audioSession
        self.remoteCommandCenter = remoteCommandCenter
        self.sessionActivationRetryDelay = sessionActivationRetryDelay
        self.backgroundTasks = backgroundTasks
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.startupWatchdogDeadline = startupWatchdogDeadline
        self.startupWatchdogSleep = startupWatchdogSleep
        self.reachability = reachability
        self.defaults = defaults
        self.heartbeatInterval = heartbeatInterval

        // NOTE: We intentionally do NOT call configureAudioSessionIfNeeded() here.
        // Setting the audio session category to .playback during init interrupts
        // other apps' audio. Configuration is deferred until play() is called.
        setUpRemoteCommandCenter()
        setUpNotifications()
        setUpPlayerObservation()
        setUpCPUAggregator()
        setUpHeartbeat()
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
        defaults: DefaultsStorage = UserDefaults.standard,
        heartbeatInterval: Duration = .seconds(60),
        startupWatchdogSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.player = player
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer
        self.startupWatchdogDeadline = startupWatchdogDeadline
        self.startupWatchdogSleep = startupWatchdogSleep
        self.reachability = reachability
        self.defaults = defaults
        self.heartbeatInterval = heartbeatInterval

        setUpPlayerObservation()
        setUpCPUAggregator()
        setUpHeartbeat()
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
        heartbeat?.stop()
        #if os(iOS) || os(tvOS)
        sessionActivationRetryTask?.cancel()
        // interruptionRouteHandler's own deinit removes its notification
        // observers; nothing to do here beyond releasing the reference,
        // which happens automatically once this deinit body returns.
        removeRemoteCommandTargets()
        #endif
    }

    // MARK: - Public Methods

    /// Toggle playback state
    /// - Parameter reason: Why playback was toggled (for analytics)
    public func toggle(reason: PlaybackReason) {
        if isPlaying {
            stopWithAnalytics(reason: reason)
        } else {
            play(reason: reason)
        }
    }

    /// Captures a `PlaybackStoppedEvent` — attributing `source` from `reason`
    /// (#668) — and then stops. The free-text `reason` string is deliberately
    /// withheld here (matches the pre-existing "user-initiated stops report a
    /// nil reason" contract), but `source` is never nil: this is what closes
    /// the "user pauses carry no attribution" gap, since every stop site
    /// knows its `PlaybackReason` even when it doesn't want to surface the
    /// free-text string. Shared by `toggle(reason:)`'s stop branch and the
    /// remote pause command target in `setUpRemoteCommandCenter()` so both
    /// paths — one directly testable, one gated behind a real
    /// `MPRemoteCommandEvent` a unit test can't construct — stay identical.
    private func stopWithAnalytics(reason: PlaybackReason) {
        analytics.capture(PlaybackStoppedEvent(source: reason.playbackSource, duration: playbackDuration, sessionID: sessionID))
        stop(reason: reason)
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
        // Fresh session: clear any stale park state from a prior listen so the
        // startup watchdog doesn't defer against a park that already resolved.
        // The streamer re-announces a real park via `.connectivityWaitChanged`. #699.
        isPlayerWaitingForConnectivity = false
        playbackTimer = playbackTimer ?? Core.Timer.start()
        sessionID = sessionID ?? UUID().uuidString
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
        analytics.capture(PlaybackStartedEvent(reason: reason.rawValue, source: reason.playbackSource, sessionID: sessionID))
        donatePlayIntent()
    }
    
    /// Calculate how long playback has been active
    private var playbackDuration: TimeInterval {
        playbackTimer?.duration() ?? 0
    }

    /// Stop playback and disconnect from stream
    /// - Parameter reason: Why playback was stopped (for analytics)
    public func stop(reason: PlaybackReason) {
        Log(.info, category: .playback, "Stop requested (reason: \(reason.rawValue))")
        cpuAggregator?.endSession(reason: .userStopped)

        leaveHoldingPattern()
        disarmStartupWatchdog()
        // Shared six-step teardown (#755): cancels the reconnect, resets
        // backoff, stops the heartbeat, clears playback intent, and applies
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
            sessionID: &sessionID
        )

        stallStartTime = nil
        player.stop()
        playerState = player.state
        playbackTimer = nil
        #if os(iOS) || os(tvOS)
        // Cancel any deferred session-activation retry — the user (or system)
        // no longer wants playback, so we must not keep trying to interrupt.
        clearPendingSessionActivation()
        scheduleAudioSessionDeactivation()
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

    /// Prepares the audio session for playback without actually starting playback.
    /// Call this at the start of an intent to signal to iOS that audio playback is
    /// imminent, which helps prevent the app from being suspended during stream
    /// connection.
    ///
    /// On macOS (native AppKit) and watchOS there is no `AVAudioSession` to
    /// configure, so this is a no-op. The method stays available on every platform
    /// so the shared intent call sites (`IntentPlayback`, `ToggleWXYC`,
    /// `WidgetToggleWXYC`) need no `#if` branch of their own.
    public func prepareForPlayback() {
        #if os(iOS) || os(tvOS)
        configureAudioSessionIfNeeded()
        activateAudioSession()
        #endif
    }

    // MARK: - Audio Session (iOS/tvOS only)

    #if os(iOS) || os(tvOS)
    /// Audio session category is configured lazily on first play() to avoid
    /// interrupting other apps' audio during app launch.
    private var audioSessionConfigured = false

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
            try activate(session)
            audioSessionActivated = true
            clearPendingSessionActivation()
            Log(.info, category: .playback, "Audio session activated")
            return true
        } catch is AudioSessionBusy {
            // Deliberately *not* routed into the bounded retry. That budget —
            // four attempts, one second in total — is sized for another app
            // holding the session, and it is shorter than this handback can be:
            // the block this class exists to move off the main actor was itself
            // measured at about a second. Polling would exhaust first, clear
            // `pendingPlaybackReason`, and abandon the play with `playbackIntended`
            // still set, leaving a spinner until the startup watchdog escalates.
            //
            // `AudioSessionBusy` is thrown only while a handback holds the lock,
            // so a continuation is guaranteed to run and re-drive this from
            // `resumeDeferredActivationAfterHandback()` — a wait proportional to
            // the handback instead of to a fixed budget. Marking the activation
            // pending is what makes `play()` defer rather than escalate, and it
            // is deliberately not gated on `isForegrounded`: the resumes that
            // collide with a handback (an interruption ending, a lock-screen or
            // CarPlay play, a route flap) arrive precisely when backgrounded.
            Log(.info, category: .playback, "Audio session still being handed back; deferring activation until it completes")
            sessionActivationPending = true
            return false
        } catch {
            Log(.error, category: .playback, "Failed to activate audio session: \(error)")
            if isCannotInterruptOthers(error) {
                scheduleSessionActivationRetry(cause: .cannotInterruptOthers)
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

    /// Why an activation had to be deferred. Every case here means *another app*
    /// holds the session; this app's own in-flight handback is handled by
    /// `resumeDeferredActivationAfterHandback()` instead, precisely because it is
    /// the one blocker whose completion can be observed rather than polled for.
    /// The causes ride the same retry cadence but are very different diagnoses,
    /// so they must not be conflated in the field.
    private enum ActivationRetryCause: String {
        /// Another app holds the session and declines to be interrupted.
        case cannotInterruptOthers = "CannotInterruptOthers"
        /// An interruption ended but the session still won't activate.
        case stillBlockedAfterInterruption = "still blocked after interruption ended"
        /// Our handback finished but the session still won't activate.
        case stillBlockedAfterHandback = "still blocked after handback"
    }

    /// Schedules a bounded, delayed sequence of activation retries after a
    /// `CannotInterruptOthers` failure. Deliberately does NOT busy-loop: it
    /// spaces attempts out and stops after `maxSessionActivationRetries`, and an
    /// interruption-ended notification can short-circuit the wait via
    /// `reactivateAfterInterruptionIfPending()`.
    private func scheduleSessionActivationRetry(cause: ActivationRetryCause) {
        // Never activate while backgrounded — foregrounding drives its own
        // reactivation path — and only when playback is still intended.
        guard playbackIntended, isForegrounded else { return }
        // A retry is already in flight; let it run to completion.
        guard !sessionActivationPending else { return }

        sessionActivationPending = true
        Log(.info, category: .playback, "Audio session activation deferred (\(cause.rawValue)); scheduling bounded retry")

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

                switch self.retrySessionActivation() {
                case .activated, .deferredBehindHandback:
                    // Done, or parked on our own handback's completion — either
                    // way this cadence has nothing further to add.
                    return
                case .blockedByOtherAudio, .failed:
                    continue
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

    /// What a single deferred-activation attempt did. Callers must not conflate
    /// these: a session busy with our *own* handback is re-driven by that
    /// handback's continuation and must stay parked on it, while a session held
    /// by another app is the bounded retry's territory, and a hard failure is
    /// neither — collapsing them (as a plain Bool once did) demoted the
    /// event-driven wait onto a budget shorter than the handback it was waiting
    /// out, which exhausted, cleared `pendingPlaybackReason`, and abandoned the
    /// play.
    private enum SessionActivationRetryOutcome {
        /// The session activated; any deferred play has been resumed.
        case activated
        /// Our own in-flight handback holds the session. The deferral stays
        /// intact and the handback continuation re-drives it.
        case deferredBehindHandback
        /// Another app holds the session (`'!int'`) — the transient state the
        /// bounded retry cadence is sized for.
        case blockedByOtherAudio
        /// A non-transient activation failure.
        case failed(any Error)
    }

    /// Attempts a single (re)activation of the session and, on success, resumes
    /// the deferred playback.
    private func retrySessionActivation() -> SessionActivationRetryOutcome {
        guard let session = audioSession else { return .activated }
        configureAudioSessionIfNeeded()
        do {
            try activate(session)
            audioSessionActivated = true
            let reason = pendingPlaybackReason
            clearPendingSessionActivation()
            Log(.info, category: .playback, "Audio session activated after deferred retry")
            // Consult the live player, not the mirrored `isPlaying`: the mirror
            // lags the state stream, and a stale `.playing` replayed from
            // before the stop would skip the start here while still consuming
            // the deferral — the play would be silently dropped. Same
            // divergence `armStartupWatchdog()`'s deadline check guards against.
            if let reason, playbackIntended, !player.isPlaying {
                startPlayerAfterActivation(reason: reason)
            }
            return .activated
        } catch is AudioSessionBusy {
            // Same contract as `activateAudioSession()`'s Busy branch: the
            // handback continuation is guaranteed to run and re-drive this via
            // `resumeDeferredActivationAfterHandback()`, so the deferral stays
            // parked on that completion rather than on any polled budget.
            Log(.info, category: .playback, "Audio session still being handed back; keeping the deferred activation parked on its completion")
            sessionActivationPending = true
            return .deferredBehindHandback
        } catch {
            Log(.info, category: .playback, "Deferred audio session activation still blocked: \(error)")
            return isCannotInterruptOthers(error) ? .blockedByOtherAudio : .failed(error)
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
        switch retrySessionActivation() {
        case .activated, .deferredBehindHandback:
            // Done, or parked on our own handback — the one blocker whose
            // completion is observable rather than polled for.
            break
        case .blockedByOtherAudio, .failed:
            // Still blocked — resume the bounded retry cadence. Reached only
            // from an interruption-ended notification, so the interruption is
            // the cause worth naming here rather than whatever `activate(_:)`
            // last threw.
            sessionActivationPending = false
            scheduleSessionActivationRetry(cause: .stillBlockedAfterInterruption)
        }
    }

    /// Clears any deferred-activation bookkeeping and cancels the retry task.
    private func clearPendingSessionActivation() {
        sessionActivationPending = false
        pendingPlaybackReason = nil
        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = nil
    }

    /// Thrown by `activate(_:)` when a deferred deactivation currently owns the
    /// session. Not a failure of the activation itself — the caller defers and
    /// retries instead of treating it as an error.
    private struct AudioSessionBusy: Error {}

    /// Activates the session under `sessionLock`, bumping the generation so any
    /// deactivation scheduled before this point recognises itself as stale.
    /// A failed activation deliberately leaves the generation alone.
    ///
    /// Takes the lock only if it is free. An unavailable lock means the deferred
    /// deactivation is mid-`setActive(false, …)` — the very
    /// hundreds-of-milliseconds XPC call this class moved off the main actor.
    /// Blocking on it here would just relocate the freeze from the pause tap to
    /// the play tap, so the caller defers to the bounded retry instead.
    private func activate(_ session: AudioSessionProtocol) throws {
        guard sessionLock.lockIfAvailable() else { throw AudioSessionBusy() }
        defer { sessionLock.unlock() }
        try session.setActive(true, options: [])
        sessionActivationGeneration &+= 1
        // Audio is running again, so we are demonstrably not out of background
        // time any more and the next handback may arm an assertion. Deliberately
        // after the `setActive`, so a throw leaves the latch alone.
        handbackAssertionsExpired = false
    }

    /// Hands the audio session back to the system, off the caller's turn.
    ///
    /// `setActive(false, options: .notifyOthersOnDeactivation)` is a synchronous
    /// XPC round-trip to `mediaserverd` that also fans resume notifications out
    /// to every other audio app on the device; on a real device it routinely
    /// costs hundreds of milliseconds. Running it inline in `stop()` charged that
    /// latency to the caller — and because SwiftUI cannot render until the tap
    /// handler returns, the pause button and the LCD visualizer both stayed
    /// frozen for the duration. Nothing the UI reads depends on the deactivation
    /// having completed, so it moves to a background executor — and `activate(_:)`
    /// declines to wait on it, deferring to the bounded retry instead, so the
    /// freeze can't reappear on the play tap either.
    ///
    /// `audioSessionActivated` is cleared only once the handback is *confirmed*,
    /// so a failed deactivation leaves it set and the next `stop()` tries again
    /// rather than early-returning on a session the OS still considers active.
    /// `sessionDeactivationInFlight` covers the window in its place.
    private func scheduleAudioSessionDeactivation() {
        // Only deactivate if we previously activated - AVAudioSession has no isActive property
        guard audioSessionActivated, audioSession != nil else { return }
        guard !sessionDeactivationInFlight else {
            // Don't stack a second XPC call behind the first — but don't drop the
            // request either. The in-flight handback may yet decline as stale,
            // because a `play()` re-activated the session after it was scheduled,
            // and then this request is the only thing left that would ever hand
            // the session back. Re-driven from the continuation below.
            sessionDeactivationRequested = true
            return
        }
        sessionDeactivationInFlight = true

        // Taken here, where the handback is *scheduled*, rather than where the
        // app is backgrounded: by the time `handleAppDidEnterBackground()` runs
        // the handback is already in flight, and an assertion begun then would
        // cover only the tail of it. Beginning it while still foregrounded is
        // the documented usage — the assertion is what buys the seconds after
        // the transition, whenever the transition happens to arrive.
        let assertion = beginHandbackAssertion()

        // Read without the lock, deliberately. `sessionActivationGeneration` is
        // written only by `activate(_:)`, which is main-actor isolated, so this
        // read races nobody; the detached deactivation takes the lock only
        // because it reads from off the actor. Taking it here would be actively
        // harmful — it is a *blocking* acquire on the main actor, and the thing
        // that holds it holds it across the very XPC call this all exists to
        // get off the main actor.
        let generation = sessionActivationGeneration

        // The outer task inherits the main actor but doesn't run until this turn
        // ends, and the blocking call happens on the detached one — so `stop()`
        // still returns immediately, and the bookkeeping lands back on the actor
        // without an explicit `MainActor.run`. `self` is captured strongly on
        // purpose: the handback is what lets every other audio app resume, so it
        // has to finish even if the controller is being torn down. (That is also
        // why no handle to this task is kept: there is nothing `deinit` should
        // cancel, and cancelling would be pointless rather than dangerous, since
        // the detached child doesn't inherit cancellation and `.value` on a
        // non-throwing task never checks it.)
        Task { [self] in
            let handedBack = await Task.detached(priority: .userInitiated) {
                self.deactivateAudioSession(ifGenerationIs: generation)
            }.value
            sessionDeactivationInFlight = false
            // `handedBack` proves the session was handed back at some point — not
            // that it is still down now. The detached task released the lock
            // before this continuation was scheduled, and a deferred activation
            // retry can have taken it and re-activated in between. Clearing the
            // flag on that ordering would strand a live session: every later
            // `stop()` would early-return on it, and the session would never be
            // handed back at all.
            if handedBack, sessionActivationGeneration == generation {
                audioSessionActivated = false
            }
            resumeDeferredActivationAfterHandback()
            drainRequestedSessionDeactivation()
            // Released *after* the drain, so a re-driven handback has already
            // taken its own assertion by the time this one lets go. Releasing
            // first would leave the app holding none for exactly the window the
            // re-driven handback runs in — and that handback is the one that
            // actually hands the session back, since this one declined as stale.
            endHandbackAssertion(assertion)
        }
    }

    /// Asks the system to keep the process running until the deferred handback
    /// finishes, so a background transition arriving mid-handback can't strand
    /// it. Returns nil when there is no provider (every construction site but
    /// `shared`), when the system declined, or when our background time has
    /// already expired — in all three the handback runs exactly as it did
    /// before this seam existed: unprotected, but never blocked.
    ///
    /// Called on the caller's turn, from inside `stop()`. `beginBackgroundTask`
    /// is a `runningboardd` round-trip rather than the `mediaserverd` one #774
    /// moved off the main actor, and is orders of magnitude cheaper — but it is
    /// not free, and it is on the tap path, so it is worth re-measuring on a
    /// device if pause latency ever regresses. Note that
    /// `stopPublishesPausedStateBeforeDeactivating` cannot catch that: the mock
    /// is a dictionary insert and measures nothing about the real call.
    private func beginHandbackAssertion() -> BackgroundTaskID? {
        guard let backgroundTasks, !handbackAssertionsExpired else { return nil }
        // `[weak self]` where the task two frames up captures strongly, on
        // purpose but not obviously: an assertion is live only while that task
        // is, and that task holds the controller, so `self` is provably non-nil
        // for the handler's whole window. If it somehow weren't, the assertion
        // would never be ended and the OS would kill us — hence the note.
        let id = backgroundTasks.beginTask(named: "Audio session handback") { [weak self] in
            // Expiration is app-wide rather than per-assertion — the granted
            // time ran out — so every assertion this controller holds is about
            // to become fatal, and all of them are released together.
            //
            // Deliberately *only* released: the handback is not forced to
            // completion here. A `setActive(false, …)` still outstanding after
            // the whole background grace period is wedged in `mediaserverd`, and
            // a second one issued from this handler could only stack behind it —
            // while waiting on `sessionLock` to issue it safely would block the
            // main actor, which is both the defect #774 fixed and, with seconds
            // left before termination, a watchdog kill. Letting it lapse costs
            // one deferred handback; `audioSessionActivated` stays set on an
            // unconfirmed one, so the next `stop()` retries it — the contract
            // `failedDeactivationStaysRetryable` pins — as does the next
            // background transition, which finds the flag still set and hands
            // back synchronously. Foregrounding is *not* one of the retry
            // drivers: `handleAppWillEnterForeground()` touches the session only
            // when `playbackIntended`, and a pause is precisely the state where
            // it isn't.
            self?.endAllHandbackAssertions()
        }
        guard let id else { return nil }
        liveHandbackAssertions.insert(id)
        return id
    }

    /// Releases every assertion this controller still holds, and latches the
    /// expiry so nothing arms another one. Used only from the expiration
    /// handler, where the alternative is termination.
    private func endAllHandbackAssertions() {
        // The only signal that a real listener's other audio app stayed
        // suppressed. Everything else in this file's handback path logs; this is
        // the branch where the handback is knowingly abandoned, so it logs
        // loudest.
        Log(
            .error,
            category: .playback,
            "Background time expired with \(liveHandbackAssertions.count) handback assertion(s) live; releasing them and letting the handback lapse"
        )
        handbackAssertionsExpired = true
        let live = liveHandbackAssertions
        liveHandbackAssertions.removeAll()
        for id in live {
            backgroundTasks?.endTask(id)
        }
    }

    /// Releases one assertion, if it is still live. Membership in
    /// `liveHandbackAssertions` is what makes this idempotent: ending the same
    /// assertion twice is a programming error `UIApplication` raises on.
    ///
    /// Relies on identifiers never being recycled within a process, which
    /// `UIApplication` guarantees by assigning them from a monotonic counter. If
    /// they were reused, an expired assertion's late end could match a newer
    /// one's entry and release it early.
    private func endHandbackAssertion(_ id: BackgroundTaskID?) {
        guard let id, liveHandbackAssertions.remove(id) != nil else { return }
        backgroundTasks?.endTask(id)
    }

    /// Re-drives an activation that deferred behind the handback, now that the
    /// handback has released the session.
    ///
    /// This is the whole reason `activateAudioSession()` doesn't poll for its own
    /// handback: the completion is observable, so the wait is proportional to the
    /// handback instead of to a budget that is shorter than one.
    private func resumeDeferredActivationAfterHandback() {
        guard sessionActivationPending else { return }
        guard playbackIntended else {
            // The play that deferred has since been cancelled. Clear the
            // bookkeeping rather than leaving `sessionActivationPending` latched,
            // which would make every later activation look like it already had a
            // retry in flight.
            clearPendingSessionActivation()
            return
        }
        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = nil
        switch retrySessionActivation() {
        case .activated:
            break
        case .deferredBehindHandback:
            // A second handback (a drain re-drive) took the lock between this
            // one's completion and the retry; its own continuation re-enters
            // here when it finishes.
            break
        case .blockedByOtherAudio:
            // Blocked by something other than our own handback now, so this
            // genuinely is the `CannotInterruptOthers` shape the bounded retry
            // was sized for. If it declines to schedule — backgrounded, where
            // foregrounding drives its own reactivation — drop the deferral
            // rather than leaving `play()` waiting on a driver that will never
            // run. The startup watchdog armed at play time still covers it.
            sessionActivationPending = false
            scheduleSessionActivationRetry(cause: .stillBlockedAfterHandback)
            if !sessionActivationPending {
                pendingPlaybackReason = nil
            }
        case .failed:
            // A hard, non-`'!int'` failure — the same class that escalates
            // immediately when it surfaces in `play()` (#518, design 6-A). The
            // bounded retry can't help (it exists for another app declining to
            // be interrupted, and its exhaustion path gives up without
            // escalating), so spending it here would just delay the same
            // silence signal by the rest of the watchdog deadline.
            clearPendingSessionActivation()
            Log(.error, category: .playback, "Audio session activation failed after handback; escalating silent-startup recovery immediately")
            escalateSilentStartup(description: "Audio session activation failed after handback")
        }
    }

    /// Re-drives a handback request that arrived while one was already in flight.
    ///
    /// Gated on playback still being unintended: the dropped request may have
    /// been overtaken by a `play()`, and tearing down *that* session is exactly
    /// the failure the generation check exists to prevent. Each rejected request
    /// re-drives at most once, so a persistently failing handback can't turn this
    /// into an unbounded XPC loop — the next `stop()` retries it instead, which
    /// is the contract `failedDeactivationStaysRetryable` pins.
    private func drainRequestedSessionDeactivation() {
        guard sessionDeactivationRequested else { return }
        sessionDeactivationRequested = false
        guard !playbackIntended else { return }
        scheduleAudioSessionDeactivation()
    }

    /// Hands the session back on the caller's turn, for the one call site where
    /// deferring buys nothing and costs a guarantee: the app entering the
    /// background. No view is waiting to render there, so the latency is
    /// invisible — but a deferred handback is racing suspension, and if it loses,
    /// `.notifyOthersOnDeactivation` never fires and the app whose audio we
    /// interrupted stays silent until WXYC is next resumed. This is what the call
    /// site did before the handback was deferred at all.
    ///
    /// Runs entirely within the caller's turn, and the system does not suspend an
    /// app inside its own scenePhase callback — so this path needs no
    /// background-execution assertion of its own.
    private func deactivateAudioSessionOnCallersTurn() {
        guard audioSessionActivated, audioSession != nil else { return }
        guard !sessionDeactivationInFlight else {
            // One is already running and will finish or re-drive itself. Blocking
            // on its lock is the one thing this must not do.
            //
            // This is the ordering #776 was about: the in-flight handback's
            // continuation is what re-drives this request, and it was racing
            // suspension. It no longer is — the assertion taken when that
            // handback was *scheduled*, if the system granted one, is still live
            // and outlives the drain. Where none was granted the race is exactly
            // what it was before, which is the floor this seam degrades to.
            sessionDeactivationRequested = true
            return
        }
        if deactivateAudioSession(ifGenerationIs: sessionActivationGeneration) {
            audioSessionActivated = false
        }
    }

    /// Performs the deactivation unless the session has been activated again
    /// since it was scheduled.
    ///
    /// Both halves of the check-then-act run under `sessionLock`, so a `play()`
    /// racing this from the main actor either completes first — and this call
    /// sees the bumped generation and declines — or finds the lock taken and
    /// defers, re-activating on the bounded retry once this has finished.
    /// `Task.cancel()` alone can't close that window: cancellation is
    /// cooperative, and by the time `play()` runs this may already be inside
    /// `setActive`.
    ///
    /// - Returns: Whether the session was actually handed back. `false` covers
    ///   both a failure (the OS still holds it active, so the caller must keep
    ///   `audioSessionActivated` set and retry later) and a stale attempt (a
    ///   `play()` re-activated it, and already set the flag itself).
    private nonisolated func deactivateAudioSession(ifGenerationIs expected: Int) -> Bool {
        guard let session = audioSession else { return false }

        let outcome: DeactivationOutcome
        sessionLock.lock()
        if sessionActivationGeneration != expected {
            outcome = .stale
        } else {
            // Timed because this call's cost is the whole reason it isn't on the
            // main actor, and it is only visible on a real device — the simulator
            // returns in about a millisecond, which is what made this hard to see.
            let timer = Core.Timer.start()
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                outcome = .deactivated(timer.duration())
            } catch {
                outcome = .failed(error)
            }
        }
        sessionLock.unlock()

        // Logged outside the lock — it writes to disk, and the main actor may be
        // waiting on this lock to activate.
        switch outcome {
        case .deactivated(let seconds):
            Log(.info, category: .playback, "Audio session deactivated in \(Int(seconds * 1000))ms")
            return true
        case .failed(let error):
            Log(.error, category: .playback, "Failed to deactivate audio session: \(error)")
            return false
        case .stale:
            Log(.info, category: .playback, "Skipped deferred audio session deactivation; session was re-activated")
            return false
        }
    }

    /// What a deferred deactivation attempt did, carried out of the lock so the
    /// logging that describes it doesn't happen while holding it.
    private enum DeactivationOutcome {
        case deactivated(TimeInterval)
        case failed(any Error)
        case stale
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
                self.stopWithAnalytics(reason: .remotePauseCommand)
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
    /// Constructs the shared `PlaybackInterruptionRouteHandler` (#756). This
    /// controller's only genuine extra beyond the shared switch is
    /// `reactivateAfterInterruptionIfPending()` on an `.ended` that isn't
    /// resuming prior playback — everything else (the `.interrupted` state,
    /// the `InterruptionEvent` capture, the route-change restart fallback) is
    /// `RadioPlayerController`-only and left at the handler's no-op defaults
    /// here.
    private func setUpNotifications() {
        interruptionRouteHandler = PlaybackInterruptionRouteHandler(
            notificationCenter: notificationCenter,
            isPlaying: { [weak self] in self?.isPlaying ?? false },
            sessionID: { [weak self] in self?.sessionID },
            playbackDuration: { [weak self] in self?.playbackDuration ?? 0 },
            analytics: analytics,
            stop: { [weak self] reason in self?.stop(reason: reason) },
            play: { [weak self] reason in self?.play(reason: reason) },
            getWasPlayingBeforeRouteDisconnect: { [weak self] in self?.wasPlayingBeforeRouteDisconnect ?? false },
            setWasPlayingBeforeRouteDisconnect: { [weak self] value in self?.wasPlayingBeforeRouteDisconnect = value },
            onInterruptionEndedWithoutResume: { [weak self] in self?.reactivateAfterInterruptionIfPending() }
        )
    }
    #endif

    // MARK: - App Lifecycle (iOS only)
    // These methods should be called from SwiftUI's scenePhase handler
    // rather than using UIApplication notifications, to avoid race conditions
        
    #if os(iOS)
    /// Call this when the app enters the background (from SwiftUI scenePhase)
    /// Only hands the audio session back if playback is NOT intended
    public func handleAppDidEnterBackground() {
        Log(.info, category: .playback, "App entered background (playbackIntended: \(playbackIntended))")
        isForegrounded = false

        // Abandon any in-flight session-activation retry. The retry loop can't
        // run while backgrounded (it bails on `isForegrounded`), and a bailed
        // loop leaves `sessionActivationPending` set — which would make the
        // foreground reactivation path early-out of `scheduleSessionActivationRetry`
        // and never reschedule, stranding playback (#514). Foregrounding
        // re-drives activation from scratch via `handleAppWillEnterForeground`.
        //
        // Not when the deferral is keyed to an in-flight handback, though. That
        // deferral's driver is `resumeDeferredActivationAfterHandback()`, which
        // is deliberately not foreground-gated — a pause → play → lock-the-phone
        // sequence must still start playing once the handback completes, and
        // clearing here severs the continuation's only re-drive key, losing the
        // play until the next foreground. The continuation is guaranteed to run
        // whenever the flag is set (backgrounding can observe the flag only
        // before the continuation's turn), and it cleans this bookkeeping up
        // itself when the play can't proceed.
        if !sessionDeactivationInFlight {
            clearPendingSessionActivation()
        }

        // Suspend render tap - no point running visualization in background
        if renderTapDesired {
            player.removeRenderTap()
        }

        if isPlaying {
            cpuAggregator?.transitionContext(to: .background)
        }
        guard !playbackIntended else { return }
        // Deliberately *not* deferred, unlike `stop()`'s handback: see
        // `deactivateAudioSessionOnCallersTurn()`. Nothing is rendering during a
        // background transition, so there is no latency to save here — only a
        // completion guarantee to lose.
        deactivateAudioSessionOnCallersTurn()
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

    // MARK: - Intent Donation

    /// Donates an INPlayMediaIntent to Siri so WXYC appears in Lock Screen suggestions.
    /// iOS learns from these donations to surface the app based on user listening patterns.
    /// Routes through `MediaIntentBuilder` (#828) so this donation shares the
    /// same identity — identifier, title, `resumePlayback` — as the
    /// launch-time donation in `WXYCApp.makeSiriIntentInteraction()`; nil
    /// artwork here is a deliberate choice, not the builder's default (see
    /// its doc comment).
    private func donatePlayIntent() {
        #if canImport(Intents) && !os(macOS)
        let intent = MediaIntentBuilder.makePlayMediaIntent(artwork: nil)
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
                    self.startHeartbeat()
                } else {
                    // Any non-playing state (idle, loading, stalled, error) means
                    // the listener isn't hearing audio right now — stop the
                    // cadence so a stall or a mid-reconnect gap doesn't keep
                    // emitting heartbeats for time that wasn't actually played.
                    // `startHeartbeat()` above resumes it if/when playback
                    // genuinely recovers. See #666.
                    self.stopHeartbeat()
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
                case .extendedOfflinePark(let duration):
                    handleExtendedOfflinePark(duration: duration)
                case .connectivityWaitChanged(let isWaiting):
                    // Mirror the streamer's #697 park gate so the startup
                    // watchdog can defer rather than escalate while offline. No
                    // arm/disarm here — the flag is consulted at watchdog fire
                    // time — so a stray edge after stop() is harmless. See #699.
                    self.isPlayerWaitingForConnectivity = isWaiting
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
                        recoveryMethod: .automaticReconnect,
                        sessionID: self.sessionID
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
        // Deliberately does NOT capture a `pause` event (#667): a stall is not
        // a session end, and the previous "stalled"-reason `PlaybackStoppedEvent`
        // here double-counted the same elapsed seconds into the `pause.duration`
        // average once per stall in a stally session. The reliability signal
        // already lives in `StallRecoveryEvent` / `StreamErrorEvent`.
        //
        // Stop the heartbeat explicitly (#666) rather than relying solely on
        // the `player.stateStream` observer: a stall arrives over
        // `player.eventStream` and isn't guaranteed to also push a
        // `.stalled`/non-`.playing` value through the state stream (the
        // player may keep reporting a stale `.playing` state while
        // reconnecting), so listener-side silence must cancel the cadence
        // here directly. `startHeartbeat()` resumes it once a genuine
        // recovery reaches `.playing` again via the state stream.
        stopHeartbeat()

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
            timeToFirstAudio: timeToAudio,
            sessionID: sessionID
        ))
    }

    /// Captures the low-rate `ExtendedOfflineParkEvent` forwarded by the player
    /// as an `AudioPlayerInternalEvent.extendedOfflinePark`. Deliberately does
    /// NOT disarm any watchdog or touch playback intent — the park is still
    /// ongoing (the player's inner watchdog re-armed rather than escalating),
    /// so this is a mid-flight observability signal, not a terminal outcome
    /// like `.error`/`.firstAudio`. See issue #699.
    private func handleExtendedOfflinePark(duration: TimeInterval) {
        let playerType = resolvedPlayerType
        Log(.info, category: .playback, "Extended offline park after \(String(format: "%.2f", duration))s (\(playerType.rawValue))")
        analytics.capture(ExtendedOfflineParkEvent(
            playerType: playerType,
            parkDuration: duration,
            sessionID: sessionID
        ))
    }

    // MARK: - Playback Heartbeat (#666)

    /// Starts (or restarts) the periodic `playback_heartbeat` cadence. Called
    /// only when the mirrored player state reaches `.playing` (see
    /// `setUpPlayerObservation()`), so the cadence only ever runs while audio
    /// is genuinely rendering — not while loading, stalled, or stopped.
    ///
    /// Delegates to the shared `PlaybackHeartbeat` component (#755); see that
    /// type for the cancel-then-loop-sleep-emit implementation and its
    /// lifetime guarantees.
    private func startHeartbeat() {
        heartbeat?.start()
    }

    /// Stops the heartbeat cadence. Idempotent — safe to call whether or not
    /// a heartbeat is currently running. Called on every transition away from
    /// `.playing` in `setUpPlayerObservation()`, and explicitly from
    /// `stop(reason:)` for an immediate cancellation guarantee that doesn't
    /// wait on the async state-stream round-trip.
    private func stopHeartbeat() {
        heartbeat?.stop()
    }

    /// Creates the `PlaybackHeartbeat` component. Called at the end of
    /// `init` (mirroring `setUpCPUAggregator()`) because its `onTick`
    /// closure captures `self` weakly, which Swift only permits once every
    /// stored property already has a value.
    private func setUpHeartbeat() {
        heartbeat = PlaybackHeartbeat(interval: heartbeatInterval) { [weak self] in
            self?.emitHeartbeat()
        }
    }

    /// Captures one `PlaybackHeartbeatEvent` using the same monotonic
    /// duration source as `pause.duration` (#667) and the same `sessionID`
    /// (#665) threaded onto every other playback event, so a killed or
    /// never-paused session's last heartbeat is directly usable as that
    /// listen's reconstructed duration.
    private func emitHeartbeat() {
        let context: PlaybackContext = isForegrounded ? .foreground : .background
        analytics.capture(PlaybackHeartbeatEvent(
            sessionID: sessionID,
            cumulativeSeconds: playbackDuration,
            context: context,
            playerType: resolvedPlayerType
        ))
    }

    // MARK: - Startup Watchdog (#518)

    /// Arms the play-intent → first-audio watchdog. Idempotent: cancels any prior
    /// arm first, so re-entrant `play()` calls collapse to a single live timer.
    /// The timer is measured from the establishing `play()` (user intent), which
    /// is the span the `silent_startup` deadline is meant to bound.
    ///
    /// `self` is held weakly across the sleep — the deadline and the sleep
    /// closure are the only things captured by value — so an armed watchdog
    /// never extends the controller's lifetime, provided the injected
    /// `startupWatchdogSleep` does not itself capture the controller. See that
    /// parameter's note on the initializer.
    private func armStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { [weak self, deadline = startupWatchdogDeadline, sleep = startupWatchdogSleep] in
            do {
                try await sleep(deadline)
            } catch {
                // Cancellation — the ordinary disarm/re-arm path — or an
                // injected sleep that failed outright. Neither means "the
                // deadline elapsed", so neither may escalate. A `try?` here
                // would send a failed sleep straight into a `silent_startup`
                // that never happened.
                return
            }
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
        // Mirror the streamer's #697 gate at this layer (#699): a task the
        // player reports parked waiting for connectivity is offline, not
        // silently starved. Escalating here would emit a `silent_startup` AND
        // kick the reconnect ramp — which restarts the parked streamer and
        // resets its own park tracking, defeating #697 one layer up (and
        // starving `.extendedOfflinePark` of the ~2×startupTimeout it needs to
        // fire). Defer instead: re-arm so a genuine post-resume starve is still
        // caught once the park resolves, and let the low-rate
        // `.extendedOfflinePark` own the offline-park signal.
        if isPlayerWaitingForConnectivity {
            Log(.info, category: .playback, "Startup watchdog fired while the player is parked waiting for connectivity; deferring (#699)")
            armStartupWatchdog()
            return
        }
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
            recoveryMethod: .automaticReconnect,
            sessionID: sessionID
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
                recoveryMethod: .retryWithBackoff,
                sessionID: sessionID
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
            recoveryMethod: recoveryMethod,
            sessionID: sessionID
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
