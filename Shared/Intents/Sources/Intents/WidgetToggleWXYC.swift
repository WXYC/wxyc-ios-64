//
//  WidgetToggleWXYC.swift
//  Intents
//
//  Intent to toggle WXYC playback state from WXYC's own widget-style UI: the
//  Home Screen widget's Play/Pause button (`NowPlayingWidget/Views/PlayButton.swift`)
//  and the Control Center "Control Widget" toggle WXYC ships
//  (`NowPlayingWidget.swift`'s `NowPlayingControl`). A dedicated type — rather
//  than reusing `ToggleWXYC` — so both taps are distinguishable from
//  Siri/Shortcuts invoking the shared "Toggle WXYC" action (#668): all three
//  would otherwise attribute identically to `.toggleIntent`/`PlaybackSource.siri`,
//  the exact gap WXYC/wxyc-ios-64#668 calls out. `perform()` hardcodes
//  `.widgetToggle`, so the distinguishing signal is which intent type is
//  running, not a runtime-passed parameter — the same reliable,
//  per-surface-intent pattern `PlayWXYC`/`PauseWXYC`/`ToggleWXYC` already use,
//  so there's no cross-process App-Intents serialization risk to reason about.
//
//  `SetValueIntent` conformance mirrors `ToggleWXYC` purely so `NowPlayingControl`'s
//  `ControlWidgetToggle` can bind to it; `value` is otherwise unused by `perform()`,
//  same as `ToggleWXYC`. Unused is not the same as ignorable, though —
//  `SetValueIntent` makes `value` a *required*, non-defaulted parameter, and
//  WidgetKit will not fill one in: "unlike app intents you define for system
//  functionality like Siri, widgets don't resolve parameters for app intents"
//  (developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).
//  Hand the system an instance with `value` unassigned and it never enters
//  `perform()` at all. Use `init(togglingFrom:)`, never the bare `init()`.
//
//  Not discoverable and not an App Shortcut: this exists solely for WXYC's own
//  widget-style UI, not for Siri/Shortcuts/Spotlight.
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import PlaybackCore

public struct WidgetToggleWXYC: SetValueIntent, AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Toggles WXYC Playback from the widget"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Toggle WXYC (Widget)"

    @Parameter(title: "Playing")
    public var value: Bool

    public init() { }

    public init(value: Bool) {
        self.value = value
    }

    /// The initializer every widget-style control must use.
    ///
    /// `perform()` ignores `value` — it reads live playback state instead, so
    /// the control can't act on a stale render — but the parameter still has to
    /// be *assigned*, because widgets never resolve parameters (see this file's
    /// header). Taking the rendered state and flipping it here, rather than
    /// leaving `value:` to each call site, keeps the one thing the system
    /// checks impossible to forget: `Button(intent: WidgetToggleWXYC())`
    /// compiles, installs, renders, and then silently does nothing when tapped.
    ///
    /// - Parameter isPlaying: the state the control is currently rendering.
    public init(togglingFrom isPlaying: Bool) {
        self.init(value: !isPlaying)
    }

    public func perform() async throws -> some IntentResult {
        await IntentPlayback.toggleAndAwait(reason: .widgetToggle, context: "WidgetToggleWXYC intent")
        return .result()
    }

    @available(iOS 26.0, macOS 26.0, *)
    public static var supportedModes: IntentModes { [.background] }
}
