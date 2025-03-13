//
//  WXYCTVApp.swift
//  WXYC TV
//
//  Created by Jake Bromberg on 3/1/25.
//

import SwiftUI
import PostHog

@main
struct WXYCTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    init() {
        PostHogSDK.shared.capture("app launch")
    }
}

#Preview{
    ContentView()
}
