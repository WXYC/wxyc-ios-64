//
//  PlaybackInterruptionRouteHandler.swift
//  PlaybackCore
//
//  Owns the AVAudioSession interruption/route-change notification
//  subscription, the case switch over each notification's type/reason, and
//  the shared `PlaybackStoppedEvent` capture. Extracted from
//  AudioPlayerController's `handleInterruption`/`handleRouteChange` and
//  RadioPlayerController's `handleSessionInterrupted`/`handleRouteChanged`,
//  which duplicated this switch and capture verbatim. The genuine
//  per-controller differences — Radio's extra `InterruptionEvent` capture and
//  `.interrupted` state, its route-change restart fallback, and Audio's
//  deferred-session-activation reactivation — are expressed as narrow hook
//  closures rather than copies (#756).
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS)
import AVFoundation
import Analytics
import Foundation

/// Subscribes to `InterruptionMessage`/`RouteChangeMessage` and runs the
/// shared interruption/route-change state machine, delegating
/// controller-specific extras to injected hooks.
///
/// Ownership split (mirrors `PlaybackStopTeardown`'s convention): this type
/// owns `wasPlayingBeforeInterruption`, since both controllers used it
/// exclusively within this handling and nowhere else. `wasPlayingBeforeRouteDisconnect`
/// stays owned by the calling controller — `play()` and `PlaybackStopTeardown`
/// also touch it — and is threaded through via a get/set pair instead of
/// `inout`, since this type's own methods run later, asynchronously, from a
/// stored notification-observer closure rather than a direct synchronous call.
@MainActor
public final class PlaybackInterruptionRouteHandler {
    private let notificationCenter: NotificationCenter
    private let isPlaying: () -> Bool
    private let sessionID: () -> String?
    private let playbackDuration: () -> TimeInterval
    private let analytics: AnalyticsService
    private let stop: (PlaybackReason) -> Void
    private let play: (PlaybackReason) -> Void
    private let getWasPlayingBeforeRouteDisconnect: () -> Bool
    private let setWasPlayingBeforeRouteDisconnect: (Bool) -> Void
    private let onInterruptionReceived: (AVAudioSession.InterruptionType) -> Void
    private let onInterruptionWillStopForPlayback: () -> Void
    private let onInterruptionBeganHandled: () -> Void
    private let onInterruptionEndedWithoutResume: () -> Void
    private let onRouteChangeReceived: (AVAudioSession.RouteChangeReason) -> Void
    private let onRouteChangeRestartFallback: () -> Void

    /// Whether playback was active immediately before the current interruption
    /// began, so `.ended` knows whether a resume is warranted. Scoped entirely
    /// to this handler — neither controller reads it outside interruption
    /// handling — and reset to `false` at the end of every `.ended` case.
    private var wasPlayingBeforeInterruption = false

    private var interruptionObservation: (any NSObjectProtocol)?
    private var routeChangeObservation: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - notificationCenter: Observed for `InterruptionMessage` and `RouteChangeMessage`.
    ///   - isPlaying: Whether the controller is currently playing.
    ///   - sessionID: The controller's current per-listen session id (#665), for the shared `PlaybackStoppedEvent`.
    ///   - playbackDuration: The controller's current playback duration, for the shared `PlaybackStoppedEvent`.
    ///   - analytics: Sink for the shared `PlaybackStoppedEvent` capture.
    ///   - stop: Called to stop playback for a given reason (`.interruptionBegan` / `.routeDisconnected`).
    ///   - play: Called to (re)start playback for a given reason (`.resumeAfterInterruption` / `.resumeAfterRouteReconnect`).
    ///   - getWasPlayingBeforeRouteDisconnect: Reads the controller-owned flag recording whether playback was active before the last route disconnect.
    ///   - setWasPlayingBeforeRouteDisconnect: Writes that flag.
    ///   - onInterruptionReceived: Fired with the raw interruption type before the switch — e.g. for logging. Default no-op.
    ///   - onInterruptionWillStopForPlayback: Fired immediately before the shared `PlaybackStoppedEvent` capture on a `.began` that is actually stopping active playback — e.g. Radio's `InterruptionEvent` capture. Default no-op.
    ///   - onInterruptionBeganHandled: Fired unconditionally at the end of `.began` handling, whether or not playback was active — e.g. Radio's `.interrupted` state transition. Default no-op.
    ///   - onInterruptionEndedWithoutResume: Fired on `.ended` when no resume is warranted (no `.shouldResume`, or nothing was playing before the interruption) — e.g. Audio's deferred-session-activation reactivation. Default no-op.
    ///   - onRouteChangeReceived: Fired with the raw route-change reason before the switch — e.g. for logging. Default no-op.
    ///   - onRouteChangeRestartFallback: Fired for `.newDeviceAvailable` when no route-disconnect resume is warranted, and for every other route-change reason — e.g. Radio's "restart if still intended but the player already stopped" recovery. Default no-op.
    public init(
        notificationCenter: NotificationCenter,
        isPlaying: @escaping () -> Bool,
        sessionID: @escaping () -> String?,
        playbackDuration: @escaping () -> TimeInterval,
        analytics: AnalyticsService,
        stop: @escaping (PlaybackReason) -> Void,
        play: @escaping (PlaybackReason) -> Void,
        getWasPlayingBeforeRouteDisconnect: @escaping () -> Bool,
        setWasPlayingBeforeRouteDisconnect: @escaping (Bool) -> Void,
        onInterruptionReceived: @escaping (AVAudioSession.InterruptionType) -> Void = { _ in },
        onInterruptionWillStopForPlayback: @escaping () -> Void = {},
        onInterruptionBeganHandled: @escaping () -> Void = {},
        onInterruptionEndedWithoutResume: @escaping () -> Void = {},
        onRouteChangeReceived: @escaping (AVAudioSession.RouteChangeReason) -> Void = { _ in },
        onRouteChangeRestartFallback: @escaping () -> Void = {}
    ) {
        self.notificationCenter = notificationCenter
        self.isPlaying = isPlaying
        self.sessionID = sessionID
        self.playbackDuration = playbackDuration
        self.analytics = analytics
        self.stop = stop
        self.play = play
        self.getWasPlayingBeforeRouteDisconnect = getWasPlayingBeforeRouteDisconnect
        self.setWasPlayingBeforeRouteDisconnect = setWasPlayingBeforeRouteDisconnect
        self.onInterruptionReceived = onInterruptionReceived
        self.onInterruptionWillStopForPlayback = onInterruptionWillStopForPlayback
        self.onInterruptionBeganHandled = onInterruptionBeganHandled
        self.onInterruptionEndedWithoutResume = onInterruptionEndedWithoutResume
        self.onRouteChangeReceived = onRouteChangeReceived
        self.onRouteChangeRestartFallback = onRouteChangeRestartFallback

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

    @MainActor
    deinit {
        if let interruptionObservation { notificationCenter.removeObserver(interruptionObservation) }
        if let routeChangeObservation { notificationCenter.removeObserver(routeChangeObservation) }
    }

    private func handleInterruption(_ message: InterruptionMessage) {
        onInterruptionReceived(message.type)

        switch message.type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying()
            if isPlaying() {
                onInterruptionWillStopForPlayback()
                analytics.capture(PlaybackStoppedEvent(
                    reason: PlaybackReason.interruptionBegan.rawValue,
                    source: PlaybackReason.interruptionBegan.playbackSource,
                    duration: playbackDuration(),
                    sessionID: sessionID()
                ))
                stop(.interruptionBegan)
            }
            onInterruptionBeganHandled()

        case .ended:
            if message.options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                play(.resumeAfterInterruption)
            } else {
                onInterruptionEndedWithoutResume()
            }
            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ message: RouteChangeMessage) {
        onRouteChangeReceived(message.reason)

        switch message.reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - stop playback per Apple HIG.
            let wasPlaying = isPlaying()
            setWasPlayingBeforeRouteDisconnect(wasPlaying)
            if wasPlaying {
                analytics.capture(PlaybackStoppedEvent(
                    reason: PlaybackReason.routeDisconnected.rawValue,
                    source: PlaybackReason.routeDisconnected.playbackSource,
                    duration: playbackDuration(),
                    sessionID: sessionID()
                ))
                stop(.routeDisconnected)
            }

        case .newDeviceAvailable:
            // Device reconnected (e.g. AirPod reinserted) - resume if we were
            // playing before disconnect; otherwise let the fallback hook
            // decide whether a stalled player still needs restarting.
            if getWasPlayingBeforeRouteDisconnect() {
                play(.resumeAfterRouteReconnect)
            } else {
                onRouteChangeRestartFallback()
            }

        default:
            onRouteChangeRestartFallback()
        }
    }
}
#endif
