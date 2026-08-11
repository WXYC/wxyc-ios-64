//
//  PlaybackInterruptionContext.swift
//  PlaybackCore
//
//  The mandatory, non-divergent state `PlaybackInterruptionRouteHandler` reads
//  and writes on whichever controller owns it. `AudioPlayerController` and
//  `RadioPlayerController` each conform directly (#804), so a construction
//  site passes `context: self` instead of re-deriving seven individual
//  accessor closures. Deliberately narrow — this is not a general delegate
//  for the controllers' full surface (that's `PlaybackController`): the six
//  places the two controllers genuinely differ during interruption/route
//  handling stay separate optional hook closures on the handler's
//  initializer, not requirements here.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS)
import Foundation

/// Narrow, package-scoped read/write surface `PlaybackInterruptionRouteHandler`
/// needs from its owning controller. See the handler's own doc comment for
/// which of `wasPlayingBeforeRouteDisconnect` / `sessionID` / `playbackDuration`
/// each existing call site threads through.
@MainActor
package protocol PlaybackInterruptionContext: AnyObject {
    /// Whether the controller is currently playing.
    var isPlaying: Bool { get }

    /// The controller's current per-listen session id (#665), for the shared `PlaybackStoppedEvent`.
    var sessionID: String? { get }

    /// The controller's current playback duration, for the shared `PlaybackStoppedEvent`.
    var playbackDuration: TimeInterval { get }

    /// Whether playback was active immediately before the last route disconnect.
    /// Stays controller-owned rather than handler-owned — `play()` and
    /// `PlaybackStopTeardown` also touch it — so this is threaded through
    /// as a get/set pair rather than the handler holding its own copy.
    var wasPlayingBeforeRouteDisconnect: Bool { get set }

    /// Stops playback for the given reason (`.interruptionBegan` / `.routeDisconnected`).
    func stop(reason: PlaybackReason)

    /// (Re)starts playback for the given reason (`.resumeAfterInterruption` / `.resumeAfterRouteReconnect`).
    func play(reason: PlaybackReason) throws
}
#endif
