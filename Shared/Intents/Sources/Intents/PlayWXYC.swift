//
//  PlayWXYC.swift
//  Intents
//
//  Intent to play WXYC.
//
//  Created by Jake Bromberg on 01/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Logger
import Playback
import PlaybackCore

public struct PlayWXYC: AudioPlaybackIntent, InstanceDisplayRepresentable {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Plays WXYC"
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Play WXYC"

    public var displayRepresentation = DisplayRepresentation(
        title: Self.title,
        subtitle: nil,
        image: .init(systemName: "play.fill")
    )

    public init() { }

    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        Log(.info, "PlayWXYC intent")

        // Prepare audio session early to signal to iOS that audio playback is imminent
        await AudioPlayerController.shared.prepareForPlayback()

        await AudioPlayerController.shared.play(reason: .playIntent)

        // Wait for playback to start before returning, keeping the intent alive
        // so iOS doesn't suspend the app before the stream connects
        await waitForPlayback(timeout: .seconds(10))

        let value = "Tuning in to WXYC…"
        return .result(
            value: value,
            dialog: IntentDialog(stringLiteral: value)
        )
    }

    /// Waits for playback to start, polling isPlaying with a timeout.
    @MainActor
    private func waitForPlayback(timeout: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !AudioPlayerController.shared.isPlaying {
            if ContinuousClock.now >= deadline {
                Log(.warning, "PlayWXYC intent: timeout waiting for playback to start")
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        Log(.info, "PlayWXYC intent: playback started")
    }

    @available(iOS 26.0, macOS 26.0, *)
    public static var supportedModes: IntentModes { [.background] }
}

#if os(iOS)
extension PlayWXYC: ControlConfigurationIntent { }
#endif
