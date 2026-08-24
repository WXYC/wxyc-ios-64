//
//  PauseWXYC.swift
//  Intents
//
//  Intent to pause WXYC playback.
//
//  The stop goes through `IntentPlayback.stopAndPublish`, not
//  `AudioPlayerController.shared` directly, so a Siri pause updates the
//  app-group mirror the widget's Play/Pause control and the Control Center
//  toggle render. `WidgetStateService` can't cover this one: it is started from
//  the root view's `onAppear`, which an intent-driven launch never reaches, so a
//  pause spoken while the app was backgrounded left both controls offering
//  "Pause" for audio that had already stopped.
//
//  Created by Jake Bromberg on 01/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import PlaybackCore

public struct PauseWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Pauses WXYC"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Pause WXYC"

    public init() { }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        StructuredPostHogAnalytics.shared.capture(PauseWXYCIntent())
        await MainActor.run {
            IntentPlayback.stopAndPublish(reason: .pauseIntent, context: "PauseWXYC intent")
        }
        return .result(value: "Now pausing WXYC")
    }
}
