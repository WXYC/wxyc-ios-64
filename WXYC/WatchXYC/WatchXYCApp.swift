//
//  WatchXYCApp.swift
//  WatchXYC Watch App
//
//  Created by Jake Bromberg on 2/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import AVFoundation
import Logger
import PostHog
import Secrets
import Core

@main
struct WatchXYC: App {
    init() {
        let POSTHOG_API_KEY = Secrets.posthogApiKey
        let POSTHOG_HOST = "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)
        PostHogSDK.shared.setup(config)

        PostHogSDK.shared.capture("app launch")
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            Log(.error, "Could not set AVAudioSession category: \(error)")
            PostHogSDK.shared.capture(error: error, context: "AppDelegate: Could not set AVAudioSession category")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootTabView(radioPlayerController: RadioPlayerController())
        }
    }
}
