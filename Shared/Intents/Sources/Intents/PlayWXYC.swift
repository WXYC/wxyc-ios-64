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
        await AudioPlayerController.shared.play(reason: .playIntent)

        let value = "Tuning in to WXYC…"
        return .result(
            value: value,
            dialog: IntentDialog(stringLiteral: value)
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    public static var supportedModes: IntentModes { [.background] }
}

#if os(iOS)
extension PlayWXYC: ControlConfigurationIntent { }
#endif
