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
import Logger
import PostHog
import UIKit
import MusicShareKit
import Playback
import WidgetKit
import AppServices
import Playlist
import Artwork

struct IntentError: Error {
    let description: String
}

/// Helper to sync playback state with widget
/// Note: App Intents run in a separate process and cannot access SwiftUI environment,
/// so they access the shared controller directly.
@MainActor
private var playbackController: PlaybackController { AudioPlayerController.shared }

@MainActor
private func syncWidgetPlaybackState() {
    UserDefaults.wxyc.set(playbackController.isPlaying, forKey: "isPlaying")
    WidgetCenter.shared.reloadAllTimelines()
}

// App-level service access for intents
// App Intents run in a separate process and cannot access the main app's
// SwiftUI environment, so they must create their own service instances.
enum AppServices {
    @MainActor
    static func nowPlayingService() -> NowPlayingService {
        NowPlayingService(
            playlistService: PlaylistService(),
            artworkService: MultisourceArtworkService()
        )
    }
}

struct PlayWXYC: AudioPlaybackIntent, InstanceDisplayRepresentable {
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
        try await MainActor.run {
            try playbackController.play(reason: "PlayWXYC intent")
        }
        await syncWidgetPlaybackState()
        
        let value = "Tuning in to WXYC…"
        return .result(
            value: value,
            dialog: IntentDialog(stringLiteral: value)
        )
    }
    
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background] }
}

struct PauseWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Pauses WXYC"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Pause WXYC"

    public init() { }
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await MainActor.run {
            playbackController.stop()
        }
        await syncWidgetPlaybackState()
        return .result(value: "Now pausing WXYC")
    }
}

struct ToggleWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Toggles WXYC Playback"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Toggle WXYC"

    public init() { }
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await MainActor.run {
            try playbackController.toggle(reason: "ToggleWXYC intent")
        }
        await syncWidgetPlaybackState()
        return .result(value: "Now toggling WXYC")
    }
}

#if os(iOS)
extension PlayWXYC: ControlConfigurationIntent {
    
}
#endif

struct WhatsPlayingOnWXYC: AppIntent, InstanceDisplayRepresentable {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Find out what's playing on WXYC"
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "What’s Playing on WXYC?"
    
    public var displayRepresentation = DisplayRepresentation(
        title: Self.title,
        subtitle: nil,
        image: .init(named: "message.fill")
    )

    public init() { }
    public func perform() async throws -> some ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let nowPlayingService = await MainActor.run { AppServices.nowPlayingService() }

        // Get the first item from the now playing service
        var iterator = nowPlayingService.makeAsyncIterator()
        guard let nowPlayingItem = try await iterator.next() else {
            let error = IntentError(description: "Could not fetch now playing item for WhatsPlayingOnWXYC intent.")
            PostHogSDK.shared.capture(error: error, context: "fetchPlaylist")
            Log(.error, error.localizedDescription)
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

struct MakeARequest: AppIntent, InstanceDisplayRepresentable {
    public var displayRepresentation = DisplayRepresentation(
        title: Self.title,
        subtitle: nil,
        image: .init(systemName: "radio.fill")
    )
    
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Request a song on WXYC"
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Request a song on WXYC"
    
    @Parameter(title: "Request", description: "What song would you like to request?")
    var request: String

    public init() {
        
    }
    
    public func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        try await RequestService.shared.sendRequest(message: request)
        return .result(
            value: "Done",
            dialog: "Request sent!"
        )
    }
}

struct WXYCAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsPlayingOnWXYC(),
            phrases: ["What’s playing on \(.applicationName)?"],
            shortTitle: "What’s playing on WXYC?",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: PlayWXYC(),
            phrases: ["Play \(.applicationName)"],
            shortTitle: "Play WXYC",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: MakeARequest(),
            phrases: [
                "Make a request to \(.applicationName)",
                "Send a request to \(.applicationName)",
                "Request a song on \(.applicationName)",
                "Request a song for \(.applicationName)",
            ],
            shortTitle: "Send a request to WXYC",
            systemImageName: "message.fill"
        )
    }
}
