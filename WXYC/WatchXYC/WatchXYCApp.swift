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

@main
struct WatchXYC: App {
    init() {
        PostHogSDK.shared.capture("app launch")
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            Log(.error, "Could not set AVAudioSession category: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
