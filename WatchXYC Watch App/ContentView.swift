//
//  ContentView.swift
//  WatchXYC Watch App
//
//  Created by Jake Bromberg on 2/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PlayerPage()
                .tag(0)
            PlaylistPage()
                .tag(1)
            DialADJPage()
                .tag(2)
        }
        // Use PageTabViewStyle to create a page-based interface
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
    }
}

struct PlaylistPage: View {
    var body: some View {
        VStack {
            Text("Playlist Page")
                .font(.headline)
        }
        .padding()
    }
}

struct DialADJPage: View {
    var body: some View {
        VStack {
            Text("Dial A DJ Page")
                .font(.headline)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
