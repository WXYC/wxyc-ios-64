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
import PlaybackCore

public struct ToggleWXYC: SetValueIntent, AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Toggles WXYC Playback"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Toggle WXYC"

    @Parameter(title: "Playing")
    public var value: Bool

    public init() { }

    public init(value: Bool) {
        self.value = value
    }

    public func perform() async throws -> some IntentResult {
        Log(.info, "ToggleWXYC intent")

        // Prepare audio session early to signal to iOS that audio playback is imminent
        await AudioPlayerController.shared.prepareForPlayback()

        let wasPlaying = await MainActor.run {
            AudioPlayerController.shared.isPlaying
        }

        await MainActor.run {
            AudioPlayerController.shared.toggle(reason: .toggleIntent)
        }

        // If we toggled to play, wait for playback to start before returning
        // so iOS doesn't suspend the app before the stream connects
        if !wasPlaying {
            await IntentPlayback.awaitPlaybackStart(timeout: .seconds(10), context: "ToggleWXYC intent")
        }

        return .result()
    }

    @available(iOS 26.0, macOS 26.0, *)
    public static var supportedModes: IntentModes { [.background] }
}
