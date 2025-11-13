//
//  RootTabView.swift
//  WXYC
//
//  SwiftUI replacement for RootPageViewController
//

import SwiftUI
import Core

struct RootTabView: View {
    private enum Page {
        case playlist
        case infoDetail
    }
    
    @State private var selectedPage = Page.playlist

    var body: some View {
        ZStack {
            // Background image
            Image("background")
                .resizable()
                .ignoresSafeArea()

            // Page view with horizontal scrolling
            TabView(selection: $selectedPage) {
                PlaylistView()
                    .tag(Page.playlist)

                InfoDetailView()
                    .tag(Page.infoDetail)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootTabView()
        .environment(\.radioPlayerController, RadioPlayerController())
}
