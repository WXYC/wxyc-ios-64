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
///
/// The seven state accessors above (mandatory, no divergence between
/// controllers) move behind `context: PlaybackInterruptionContext` (#804),
/// holding it `weak` for the same reason every accessor closure captured its
/// controller `[weak self]` before: this handler is owned by the controller
/// it reads from, so a strong reference here would cycle.
@MainActor
public final class PlaybackInterruptionRouteHandler {
    private let notificationCenter: NotificationCenter
    private weak var context: (any PlaybackInterruptionContext)?
    private let analytics: AnalyticsService
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
    ///   - context: The mandatory, non-divergent state accessors (`isPlaying`, `sessionID`, `playbackDuration`, `wasPlayingBeforeRouteDisconnect`, `tearDown(reason:)`, `play(reason:)`) — held weakly, since this handler is owned by the same controller it reads from.
    ///   - analytics: Sink for the shared `PlaybackStoppedEvent` capture.
    ///   - onInterruptionReceived: Fired with the raw interruption type before the switch — e.g. for logging. Default no-op.
    ///   - onInterruptionWillStopForPlayback: Fired immediately before the shared `PlaybackStoppedEvent` capture on a `.began` that is actually stopping active playback — e.g. Radio's `InterruptionEvent` capture. Default no-op.
    ///   - onInterruptionBeganHandled: Fired unconditionally at the end of `.began` handling, whether or not playback was active — e.g. Radio's `.interrupted` state transition. Default no-op.
    ///   - onInterruptionEndedWithoutResume: Fired on `.ended` when no resume is warranted (no `.shouldResume`, or nothing was playing before the interruption) — e.g. Audio's deferred-session-activation reactivation. Default no-op.
    ///   - onRouteChangeReceived: Fired with the raw route-change reason before the switch — e.g. for logging. Default no-op.
    ///   - onRouteChangeRestartFallback: Fired for `.newDeviceAvailable` when no route-disconnect resume is warranted, and for every other route-change reason — e.g. Radio's "restart if still intended but the player already stopped" recovery. Default no-op. These were two distinct arms before extraction, deliberately collapsed onto one hook: Radio ran a byte-identical recovery in both, and Audio left both empty (its `default:` was an explicit `break`, on the grounds that `AudioEnginePlayer` restarts its own engine on configuration changes). The collapse is lossy for anyone wiring this hook on a controller that wants recovery **only** on a reconnect — it would also fire on `.categoryChange`, `.routeConfigurationChange`, `.override`, and `.wakeFromSleep`, which are frequent. Split it into two hooks at that point rather than accepting the wider firing.
    package init(
        notificationCenter: NotificationCenter,
        context: any PlaybackInterruptionContext,
        analytics: AnalyticsService,
        onInterruptionReceived: @escaping (AVAudioSession.InterruptionType) -> Void = { _ in },
        onInterruptionWillStopForPlayback: @escaping () -> Void = {},
        onInterruptionBeganHandled: @escaping () -> Void = {},
        onInterruptionEndedWithoutResume: @escaping () -> Void = {},
        onRouteChangeReceived: @escaping (AVAudioSession.RouteChangeReason) -> Void = { _ in },
        onRouteChangeRestartFallback: @escaping () -> Void = {}
    ) {
        self.notificationCenter = notificationCenter
        self.context = context
        self.analytics = analytics
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

    /// Retires a pending post-interruption resume, so an interruption that has
    /// begun but not yet ended will not restart playback when it does.
    ///
    /// Called from the controllers' stop path via
    /// `PlaybackStopTeardown.retireAutoResumeState(…)`, under the same
    /// reason-bounded rule as the #665 session id: a stop that is *itself* an
    /// auto-resume-bearing stop preserves the pending resume, and any other
    /// stop retires it.
    ///
    /// Without this the flag was unreachable from outside — it is set on
    /// `.began` and cleared only at the end of `.ended` — so a listener who
    /// paused from the Lock Screen during a phone call had playback restart on
    /// them the moment the call ended. That is the interruption twin of the
    /// route-disconnect case `wasPlayingBeforeRouteDisconnect` already covers.
    package func cancelPendingInterruptionResume() {
        wasPlayingBeforeInterruption = false
    }

    private func handleInterruption(_ message: InterruptionMessage) {
        onInterruptionReceived(message.type)

        switch message.type {
        case .began:
            wasPlayingBeforeInterruption = context?.isPlaying ?? false
            if context?.isPlaying ?? false {
                onInterruptionWillStopForPlayback()
                analytics.capture(PlaybackStoppedEvent(
                    reason: PlaybackReason.interruptionBegan.rawValue,
                    source: PlaybackReason.interruptionBegan.playbackSource,
                    duration: context?.playbackDuration ?? 0,
                    sessionID: context?.sessionID
                ))
                context?.tearDown(reason: .interruptionBegan)
            }
            onInterruptionBeganHandled()

        case .ended:
            if message.options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                try? context?.play(reason: .resumeAfterInterruption)
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
            let wasPlaying = context?.isPlaying ?? false
            context?.wasPlayingBeforeRouteDisconnect = wasPlaying
            if wasPlaying {
                analytics.capture(PlaybackStoppedEvent(
                    reason: PlaybackReason.routeDisconnected.rawValue,
                    source: PlaybackReason.routeDisconnected.playbackSource,
                    duration: context?.playbackDuration ?? 0,
                    sessionID: context?.sessionID
                ))
                context?.tearDown(reason: .routeDisconnected)
            }

        case .newDeviceAvailable:
            // Device reconnected (e.g. AirPod reinserted) - resume if we were
            // playing before disconnect; otherwise let the fallback hook
            // decide whether a stalled player still needs restarting.
            if context?.wasPlayingBeforeRouteDisconnect ?? false {
                try? context?.play(reason: .resumeAfterRouteReconnect)
            } else {
                onRouteChangeRestartFallback()
            }

        default:
            onRouteChangeRestartFallback()
        }
    }
}
#endif
