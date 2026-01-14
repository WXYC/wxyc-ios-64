//
//  WXUISampleApp.swift
//  WXUI
//
//  Sample app for previewing WXUI components.
//
//  Created by Jake Bromberg on 12/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
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
            }
            .navigationTitle("WXUI Components")
        }
    }
}
