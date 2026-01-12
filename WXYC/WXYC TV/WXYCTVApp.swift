//
//  WXYCTVApp.swift
//  WXYC TV
//
//  Created by Jake Bromberg on 3/1/25.
//

import SwiftUI
import PostHog
import Playback
import Playlist
import Secrets

@main
struct WXYCTVApp: App {
    private let playlistService = PlaylistService()

    var body: some Scene {
        WindowGroup {
            ContentView(playbackController: AudioPlayerController.shared)
                .environment(\.playlistService, playlistService)
        }
    }

    init() {
        PostHogSDK.shared.capture("app launch")
    }
    
    private func setUpAnalytics() {
        let config = PostHogConfig(
            apiKey: Secrets.posthogApiKey,
            host: "https://us.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["Build Configuration": buildConfiguration()])
    }
    
    private func buildConfiguration() -> String {
        #if DEBUG
        return "Debug"
        #elseif TEST_FLIGHT
        return "TestFlight"
        #else
        return "Release"
        #endif
    }
}

#Preview {
    ContentView(playbackController: AudioPlayerController.shared)
}
