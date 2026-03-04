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
import PostHog
import SwiftUI

@main
struct WatchXYC: App {
    private let playlistService = PlaylistService()

    init() {
        let config = PostHogConfig(
            apiKey: AppConfiguration.defaults.posthogApiKey,
            host: AppConfiguration.defaults.posthogHost
        )

        PostHogSDK.shared.setup(config)
        ErrorReporting.shared = PostHogErrorReporter.shared
        StructuredPostHogAnalytics.shared.capture(AppLaunchSimple())
        PostHogSDK.shared.flush()

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
}
