//
//  Intents.swift
//  WXYC
//
//  Created by Jake Bromberg on 1/10/23.
//  Copyright © 2023 WXYC. All rights reserved.
//

import Foundation
import AppIntents
import SwiftUI
import Core
import Logger
import PostHog
import UIKit

struct IntentError: Error {
    let description: String
}

public struct PlayWXYC: AudioPlaybackIntent, WidgetConfigurationIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Plays WXYC."
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "WXYC"

    public init() { }
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        PostHogSDK.shared.capture("PlayWXYC intent")
        await RadioPlayerController.shared.play()
        return .result(value: "Now playing WXYC.")
    }
}

public struct PauseWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Pauses WXYC"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Pause WXYC"

    public init() { }
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        PostHogSDK.shared.capture("PauseWXYC intent")
        await RadioPlayerController.shared.pause()
        return .result(value: "Now pausing WXYC.")
    }
}

public struct ToggleWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Toggles WXYC Playback"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Toggle WXYC"

    public init() { }
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        PostHogSDK.shared.capture("ToggleWXYC intent")
        await RadioPlayerController.shared.toggle()
        return .result(value: "Now toggling WXYC.")
    }
}

extension PlayWXYC: ControlConfigurationIntent {
    
}

public struct WhatsPlayingOnWXYC: AppIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Find out what's currently playing."
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "What’s Playing on WXYC?"

    public init() { }
    public func perform() async throws -> some ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        guard let nowPlayingItem = await NowPlayingService.shared.fetch() else {
            let error = IntentError(description: "Could not fetch now playing item for WhatsPlayingOnWXYC intent.")
            PostHogSDK.shared.capture(error: error, context: "fetchPlaylist")
            Log(.error, error.description)
            throw error
        }
        
        PostHogSDK.shared.capture("WhatsPlayingOnWXYC intent")
        let value = "\(nowPlayingItem.playcut.songTitle) by \(nowPlayingItem.playcut.artistName) is now playing on WXYC."
        return .result(
            value: value,
            dialog: IntentDialog(stringLiteral: value),
            view: NowPlayingView(item: nowPlayingItem)
        )
    }

    struct NowPlayingView: View {
        let item: NowPlayingItem

        var body: some View {
            ZStack(alignment: .bottom) {
                if let artwork = item.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFit()
                }
                
                VStack(alignment: .leading) {
                    Text(item.playcut.artistName)
                        .font(.headline)
                        .foregroundStyle(.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.playcut.songTitle)
                        .font(.subheadline)
                        .foregroundStyle(.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}

public struct WXYCAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsPlayingOnWXYC(),
            phrases: ["What’s playing on WXYC?"],
            shortTitle: "What’s playing on WXYC?",
            systemImageName: "speaker.wave.3.fill"
        )
        AppShortcut(
            intent: PlayWXYC(),
            phrases: ["Play WXYC."],
            shortTitle: "Play WXYC",
            systemImageName: "play.fill"
        )
    }
}
