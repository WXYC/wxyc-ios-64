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

public struct PlayWXYC: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "WXYC"
    public static let description = "Plays WXYC."

    public init() { }
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await RadioPlayerController.shared.play()
        return .result(value: "Now playing WXYC.")
    }
}

public struct WhatsPlayingOnWXYC: AppIntent {
    public static let title: LocalizedStringResource = "What’s Playing on WXYC?"
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let openAppWhenRun = false
    public static let description = "Find out what's currently playing."
    public static let isDiscoverable = true

    public init() { }
    public func perform() async throws -> some ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        guard let nowPlayingItem = await NowPlayingService.shared.fetch() else {
            return .result(
                value: "Something went wrong. Please try again.",
                dialog: "Something went wrong. Please try again.",
                view: EmptyView()
            )
        }
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
