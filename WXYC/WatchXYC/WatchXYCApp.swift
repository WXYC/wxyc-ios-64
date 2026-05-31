//
//  WatchXYCApp.swift
//  WXYC
//
//  App entry point for watchOS.
//
//  Created by Jake Bromberg on 02/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import AVFoundation
import Logger
import PlaybackWatchOS
import Playlist
import AppServices
import SwiftUI

@main
struct WatchXYC: App {
    private let playlistService = PlaylistService()

    init() {
        AnalyticsBootstrap.start(
            apiKey: AppConfiguration.defaults.posthogApiKey,
            host: AppConfiguration.defaults.posthogHost,
            buildConfiguration: buildConfiguration()
        )
        ErrorReporting.shared = PostHogErrorReporter.shared
        StructuredPostHogAnalytics.shared.capture(AppLaunchSimple())
        AnalyticsBootstrap.flush()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            ErrorReporting.shared.report(error, context: "WatchXYC: Could not set AVAudioSession category")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(playbackController: RadioPlayerController.shared)
                .environment(\.playlistService, playlistService)
        }
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
