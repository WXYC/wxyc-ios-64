//
//  ToggleWXYC.swift
//  Intents
//
//  Intent to toggle WXYC playback state.
//
//  Created by Jake Bromberg on 01/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Logger
import Playback

public struct ToggleWXYC: SetValueIntent, AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Toggles WXYC Playback"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Play WXYC"

    @Parameter(title: "Playing")
    public var value: Bool

    public init() { }

    public init(value: Bool) {
        self.value = value
    }

    public func perform() async throws -> some IntentResult {
        Log(.info, "ToggleWXYC intent: \(value)")
        if value {
            await AudioPlayerController.shared.play(reason: "ToggleWXYC intent")
        } else {
            await MainActor.run {
                AudioPlayerController.shared.stop(reason: "ToggleWXYC intent")
            }
        }
        return .result()
    }
}
