//
//  WXYCTVApp.swift
//  WXYC
//
//  App entry point for tvOS.
//
//  Created by Jake Bromberg on 03/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import Playback
import Playlist
import PostHog
import Secrets
import SwiftUI

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
        StructuredPostHogAnalytics.shared.capture(AppLaunchSimple())
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
