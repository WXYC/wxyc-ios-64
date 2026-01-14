//
//  WatchXYCApp.swift
//  WXYC
//
//  App entry point for watchOS.
//
//  Created by Jake Bromberg on 02/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import AVFoundation
import Logger
import PostHog
import Secrets
import Playlist
import PlaybackWatchOS
import Foundation

// #region agent log
private func debugLog(_ message: String, hypothesisId: String, data: [String: Any] = [:]) {
    let logPath = "/Users/jake/Developer/wxyc-ios-64-copy/.cursor/debug.log"
    var payload: [String: Any] = [
        "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        "location": "WatchXYCApp.swift",
        "message": message,
        "hypothesisId": hypothesisId,
        "sessionId": "debug-session"
    ]
    if !data.isEmpty { payload["data"] = data }
    if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        let line = jsonString + "\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
        }
    }
}
// #endregion

@main
struct WatchXYC: App {
    private let playlistService = PlaylistService()

    init() {
        // #region agent log
        debugLog("init() called - entry point reached", hypothesisId: "H1")
        // #endregion

        let POSTHOG_API_KEY = Secrets.posthogApiKey

        // #region agent log
        debugLog("API key retrieved", hypothesisId: "H2", data: [
            "keyLength": POSTHOG_API_KEY.count,
            "keyIsEmpty": POSTHOG_API_KEY.isEmpty,
            "keyPrefix": String(POSTHOG_API_KEY.prefix(4))
        ])
        // #endregion

        let POSTHOG_HOST = "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)

        // #region agent log
        debugLog("About to call PostHogSDK.shared.setup()", hypothesisId: "H3")
        // #endregion

        PostHogSDK.shared.setup(config)

        // #region agent log
        debugLog("PostHogSDK.setup() completed", hypothesisId: "H3")
        // #endregion

        // #region agent log
        debugLog("About to call PostHogSDK.shared.capture()", hypothesisId: "H4")
        // #endregion

        PostHogSDK.shared.capture("app launch")

        // #region agent log
        debugLog("PostHogSDK.capture() completed", hypothesisId: "H4")
        // #endregion

        // #region agent log
        debugLog("Calling PostHogSDK.shared.flush() to force send", hypothesisId: "H4-flush")
        // #endregion

        PostHogSDK.shared.flush()

        // #region agent log
        debugLog("PostHogSDK.flush() completed", hypothesisId: "H4-flush")
        // #endregion

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            Log(.error, "Could not set AVAudioSession category: \(error)")
            PostHogSDK.shared.capture(error: error, context: "AppDelegate: Could not set AVAudioSession category")
        }

        // #region agent log
        debugLog("init() completed successfully", hypothesisId: "H1")
        // #endregion
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(playbackController: RadioPlayerController.shared)
                .environment(\.playlistService, playlistService)
        }
    }
}
