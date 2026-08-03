//
//  PlaybackSource.swift
//  PlaybackCore
//
//  A clean, low-cardinality attribution surface for playback analytics (#668).
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The user-facing (or system) surface that started or stopped playback.
///
/// This is what PostHog's `play`/`pause` events should have carried all along
/// under the `source` property key. Before the analytics-architecture
/// unification (commit 8ae9813a, "Migrate AudioPlayerController to
/// PlaybackAnalytics protocol"), the old `PlaybackAnalytics.play(source:reason:)`
/// / `pause(source:duration:reason:)` protocol passed `#function` as `source` —
/// so PostHog's historical `source` property holds raw call-site names like
/// `"play(reason:)"` or `"applicationWillEnterForeground(_:)"`, not a surface.
/// That call ever since dropped `source` entirely in favor of the free-text
/// `reason` string, so every event captured since has shipped `source: null`.
/// This type — and `PlaybackReason.playbackSource` below — supersede that
/// retired property under the *same* `"source"` key (see
/// `PlaybackStartedEvent`/`PlaybackStoppedEvent`), rather than introduce a
/// second, competing property.
public enum PlaybackSource: String, Sendable, Equatable, CaseIterable {
    /// A control inside the app itself: the header view's play/pause button,
    /// a keyboard shortcut, marketing/demo mode, a Home Screen quick action
    /// or `wxyc://` deep link that launched the app to play, or the tvOS
    /// Siri Remote play/pause gesture while the app is focused.
    case app

    /// CarPlay's own WXYC now-playing screen (`CarPlaySceneDelegate`).
    /// Distinct from CarPlay's built-in steering-wheel/dash transport
    /// buttons, which arrive as `.remote` (see below).
    case carPlay

    /// WXYC's own widget-style UI: the Home Screen widget's Play/Pause button
    /// (`NowPlayingWidget/Views/PlayButton.swift`) or the Control Center
    /// "Control Widget" toggle WXYC ships (`NowPlayingControl`). Both are
    /// routed through a dedicated `WidgetToggleWXYC` intent so they're
    /// distinguishable from Siri/Shortcuts invoking the shared `ToggleWXYC`
    /// action (#668).
    case widget

    /// Siri, Shortcuts, or an App Intent: `PlayWXYC`, `PauseWXYC`,
    /// `ToggleWXYC` (when invoked via Shortcuts/Siri rather than the
    /// widget button), the iOS 27 audio-schema intent, or a replayed
    /// `INPlayMediaIntent` donation.
    case siri

    /// The watchOS app's play/pause button.
    case watch

    /// Reserved for a future distinguishing signal. `MPRemoteCommandCenter`
    /// cannot currently tell a Lock Screen tap apart from Control Center or
    /// CarPlay's built-in transport controls — all three arrive as the same
    /// `remote*` commands, so nothing maps to this case today. See `.remote`,
    /// and don't guess a mapping into this case without a real distinguishing
    /// signal (see #668's discussion of over-claiming precision).
    case lockScreen

    /// Lock Screen, Control Center, or CarPlay's built-in (steering wheel /
    /// dash) transport controls. These are genuinely indistinguishable at
    /// the `MPRemoteCommandCenter` layer — `remotePlayCommand` /
    /// `remotePauseCommand` / `remoteToggleCommand` fire identically
    /// regardless of which of the three triggered them — so they collapse
    /// into one bucket rather than guessing which surface it was.
    case remote

    /// System-driven, never a direct user action: interruption/route-
    /// disconnect auto-resume, or a foreground re-affirmation of an
    /// already-intended play/pause state.
    case auto

    /// No attributable surface: a test/dev-only `PlaybackReason`, or a
    /// reason `PlaybackReason.playbackSource` doesn't recognize.
    case unknown
}

extension PlaybackReason {
    /// Maps this reason to its clean, low-cardinality `PlaybackSource`.
    ///
    /// `PlaybackReason` is an open, string-backed set — modules outside
    /// `PlaybackCore` (the app target's `PlaybackReason+App.swift`,
    /// `PlayerHeaderView`'s `PlaybackReason+PlayerHeaderView.swift`, …) add
    /// their own reasons via extension, so this can't be an exhaustive
    /// `switch` over a closed enum. It switches on `rawValue` instead, with
    /// every known reason — including those declared outside this module —
    /// listed explicitly by literal. A reason this table doesn't recognize
    /// (e.g. a new one added later without updating this map) falls back to
    /// `.unknown` rather than failing to build: keep this list in sync
    /// whenever a new `PlaybackReason` is introduced anywhere in the app.
    public var playbackSource: PlaybackSource {
        switch rawValue {
        // Remote command center. Lock Screen, Control Center, and CarPlay's
        // built-in transport controls are indistinguishable at this layer
        // (see `PlaybackSource.remote`'s doc comment), so all three commands
        // map to the same bucket.
        case PlaybackReason.remotePlayCommand.rawValue,
             PlaybackReason.remotePauseCommand.rawValue,
             PlaybackReason.remoteToggleCommand.rawValue:
            return .remote

        // System-driven auto-resume / auto-pause paths — never a direct user action.
        case PlaybackReason.interruptionBegan.rawValue,
             PlaybackReason.resumeAfterInterruption.rawValue,
             PlaybackReason.routeDisconnected.rawValue,
             PlaybackReason.resumeAfterRouteReconnect.rawValue,
             PlaybackReason.foregroundNotPlaying.rawValue,
             PlaybackReason.foregroundToggle.rawValue,
             PlaybackReason.resumeAfterForeground.rawValue:
            return .auto

        // watchOS play/pause button.
        case PlaybackReason.watchPlayPause.rawValue:
            return .watch

        // tvOS's Siri Remote play/pause gesture fires while the app itself is
        // focused/frontmost — an in-app control, not a remote-command-center path.
        case PlaybackReason.tvOSCommand.rawValue:
            return .app

        // CarPlay's own now-playing screen.
        case PlaybackReason.carPlay.rawValue:
            return .carPlay

        // Home Screen quick action / deep link / Handoff — all three launch
        // the app to play.
        case PlaybackReason.quickAction.rawValue,
             PlaybackReason.deepLink.rawValue,
             PlaybackReason.handoff.rawValue:
            return .app

        // macOS in-app controls: the MenuBarExtra mini player and the Dock
        // right-click menu are the Mac app's own transport surfaces.
        case PlaybackReason.menuBar.rawValue,
             PlaybackReason.dockMenu.rawValue:
            return .app

        // Siri / Shortcuts / App Intents.
        case PlaybackReason.siriIntent.rawValue,
             PlaybackReason.playIntent.rawValue,
             PlaybackReason.pauseIntent.rawValue,
             PlaybackReason.toggleIntent.rawValue,
             PlaybackReason.playAudioSchemaIntent.rawValue:
            return .siri

        // WXYC's own widget-style UI (see `.widgetToggle`'s doc comment).
        case PlaybackReason.widgetToggle.rawValue:
            return .widget

        // App-target and PlayerHeaderView reasons. Declared outside
        // PlaybackCore, so referenced here by literal rather than by static
        // member — see `WXYC/iOS/PlaybackReason+App.swift` and
        // `PlayerHeaderView/PlaybackReason+PlayerHeaderView.swift`. All three
        // are in-app taps/shortcuts.
        case "header view toggle", "keyboard shortcut", "marketing mode":
            return .app

        // Test/dev-only reasons never reach production analytics.
        case PlaybackReason.test.rawValue,
             PlaybackReason.testToggle.rawValue,
             PlaybackReason.userTappedPlay.rawValue,
             PlaybackReason.userStartedStream.rawValue,
             PlaybackReason.initial.rawValue,
             PlaybackReason.errorHandlingTest.rawValue:
            return .unknown

        default:
            return .unknown
        }
    }
}
