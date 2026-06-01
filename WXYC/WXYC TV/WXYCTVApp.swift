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
import AppServices
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
        setUpAnalytics()
        StructuredPostHogAnalytics.shared.capture(AppLaunchSimple())
    }

    private func setUpAnalytics() {
        AnalyticsBootstrap.start(
            apiKey: AppConfiguration.defaults.posthogApiKey,
            host: AppConfiguration.defaults.posthogHost
        )
    }
}

#Preview {
    ContentView(playbackController: AudioPlayerController.shared)
}
