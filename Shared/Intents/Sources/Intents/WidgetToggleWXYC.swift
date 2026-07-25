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
//  same as `ToggleWXYC`.
//
//  Not discoverable and not an App Shortcut: this exists solely for WXYC's own
//  widget-style UI, not for Siri/Shortcuts/Spotlight.
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Logger
import Playback
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

    public func perform() async throws -> some IntentResult {
        Log(.info, "WidgetToggleWXYC intent")

        // Prepare audio session early to signal to iOS that audio playback is imminent
        await AudioPlayerController.shared.prepareForPlayback()

        let wasPlaying = await MainActor.run {
            AudioPlayerController.shared.isPlaying
        }

        await MainActor.run {
            AudioPlayerController.shared.toggle(reason: .widgetToggle)
        }

        // If we toggled to play, wait for playback to start before returning
        // so iOS doesn't suspend the app before the stream connects
        if !wasPlaying {
            await IntentPlayback.awaitPlaybackStart(timeout: .seconds(10), context: "WidgetToggleWXYC intent")
        }

        return .result()
    }

    @available(iOS 26.0, macOS 26.0, *)
    public static var supportedModes: IntentModes { [.background] }
}
