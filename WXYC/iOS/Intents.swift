//
//  Intents.swift
//  WXYC
//
//  Created by Jake Bromberg on 1/10/23.
//  Copyright © 2023 WXYC. All rights reserved.
//

import AppIntents
import AppServices
import Artwork
import Logger
import MusicShareKit
import Playlist
import PostHog
import SwiftUI
import UIKit
import WXYCIntents

@_exported import struct WXYCIntents.PlayWXYC
@_exported import struct WXYCIntents.PauseWXYC
@_exported import struct WXYCIntents.ToggleWXYC
@_exported import struct WXYCIntents.IntentError

// App-level service access for intents
// App Intents run in a separate process and cannot access the main app's
// SwiftUI environment, so they must create their own service instances.
enum AppIntentServices {
    @MainActor
    static func nowPlayingService() -> NowPlayingService {
        NowPlayingService(
            playlistService: PlaylistService(),
            artworkService: MultisourceArtworkService()
        )
    }
}

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
        let nowPlayingService = await AppIntentServices.nowPlayingService()

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
