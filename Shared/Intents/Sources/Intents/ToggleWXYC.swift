//
//  ToggleWXYC.swift
//  Intents
//
//  Intent to toggle WXYC playback state.
//

import AppIntents
import Playback

public struct ToggleWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Toggles WXYC Playback"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Toggle WXYC"

    public init() { }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await AudioPlayerController.shared.toggle(reason: "ToggleWXYC intent")
        return .result(value: "Now toggling WXYC")
    }
}
