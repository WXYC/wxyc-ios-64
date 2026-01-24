//
//  PauseWXYC.swift
//  Intents
//
//  Intent to pause WXYC playback.
//
//  Created by Jake Bromberg on 01/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Playback
import PlaybackCore
import PostHog

public struct PauseWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Pauses WXYC"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Pause WXYC"

    public init() { }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        PostHogSDK.shared.capture("PauseWXYC intent")
        await MainActor.run {
            AudioPlayerController.shared.stop(reason: .pauseIntent)
        }
        return .result(value: "Now pausing WXYC")
    }
}
