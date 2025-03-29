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
import Secrets

struct IntentError: Error {
    let description: String
}

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
        return .result(value: "Now pausing WXYC")
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
        return .result(value: "Now toggling WXYC")
    }
}

extension PlayWXYC: ControlConfigurationIntent {
    
}

public struct WhatsPlayingOnWXYC: AppIntent, InstanceDisplayRepresentable {
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

public struct MakeARequest: AppIntent, InstanceDisplayRepresentable {
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
        let message = "A listener has sent in a request: \(request)"
        try await sendMessageToServer(message: String(message))
        return .result(
            value: "Done",
            dialog: "Sent"
        )
    }
    
    func sendMessageToServer(message: String) async throws {
        guard let url = URL(string: Secrets.slackWxycRequestsWebhook) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-type")
        
        let json: [String: Any] = ["text": message]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else { return }
        request.httpBody = jsonData
        
        print(request)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse {
                print("Response status code: \(response.statusCode)")
            }
        } catch {
            print("Error: \(error)")
        }
    }
}

public struct WXYCAppShortcuts: AppShortcutsProvider {
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
