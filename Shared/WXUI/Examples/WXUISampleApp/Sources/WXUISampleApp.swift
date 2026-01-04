//
//  WXUISampleApp.swift
//  WXUISampleApp
//
//  Sample app for previewing WXUI components.
//

import SwiftUI

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
                NavigationLink("OverlaySheet") {
                    OverlaySheetPreview()
                }
                NavigationLink("SiriTipView") {
                    SiriTipViewPreview()
                }
            }
            .navigationTitle("WXUI Components")
        }
    }
}
