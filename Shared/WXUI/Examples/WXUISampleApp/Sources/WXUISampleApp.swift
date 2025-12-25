//
//  WXUISampleApp.swift
//  WXUISampleApp
//

import SwiftUI
import WXUI

@main
struct WXUISampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("WXYC Logo") {
                    WXYCLogoPreview()
                }
                NavigationLink("Placeholder Artwork") {
                    PlaceholderArtworkPreview()
                }
            }
            .navigationTitle("WXUI Components")
        }
    }
}
