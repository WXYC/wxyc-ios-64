//
//  PlaylistView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WXUI
import AppIntents
import DebugPanel
import PlayerHeaderView
import PartyHorn
import Playlist
import PostHog
import Wallpaper

struct PlaylistView: View {
    @State private var playlistEntries: [any PlaylistEntry] = []
    @Environment(\.playlistService) private var playlistService
    
    @State private var visualizer = VisualizerDataSource()
    @State private var selectedPlayerType = PlayerControllerType.loadPersisted()
    @State private var showVisualizerDebug = false
    @State private var showingPartyHorn = false
    @State private var showingSiriTip = false

    @Environment(Singletonia.self) var appState

    var body: some View {
        @Bindable var appState = appState
        
        ZStack {
            Color.clear
            
            ScrollView(showsIndicators: false) {
                PlayerHeaderView(
                    visualizer: visualizer,
                    selectedPlayerType: $selectedPlayerType,
                    onDebugTapped: {
                        #if DEBUG
                        showVisualizerDebug = true
                        #endif
                    }
                )

                // Siri tip
                if showingSiriTip {
                    SiriTipView(isVisible: $showingSiriTip) {
                        SiriTipView.recordDismissal()
                    }
                    .padding(.vertical, 8)
                }

                // Playlist entries
                LazyVStack(spacing: 0) {
                    ForEach(playlistEntries, id: \.id) { entry in
                        playlistRow(for: entry)
                            .padding(.vertical, 8)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: playlistEntries.map(\.id))
                    
                    // Footer button
                    if !playlistEntries.isEmpty {
                        Button("what the freq?") {
                            showingPartyHorn = true
                        }
                        .foregroundStyle(.white)
                        .fontWeight(.black)
                        .foregroundStyle(WXYCMeshAnimation())
                        .padding(.top, 20)
                        .safeAreaPadding(.bottom)
                    }
                }
            }
            .padding(.horizontal, 12)
            .coordinateSpace(name: "scroll")
        }

        .fullScreenCover(isPresented: $showingPartyHorn) {
            PartyHornSwiftUIView()
                .onAppear {
                    PostHogSDK.shared.capture("party horn presented")
                }
        }
        #if DEBUG
        .sheet(isPresented: $showVisualizerDebug) {
            VisualizerDebugView(
                visualizer: visualizer,
                selectedPlayerType: $selectedPlayerType
            )
            .presentationDetents([.fraction(0.75)])
        }
        #endif
        .onAppear {
            showingSiriTip = SiriTipView.recordLaunchAndShouldShow()
        }
        .task {
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                withAnimation {
                    self.playlistEntries = playlist.entries
                }
            }
        }
        .wallpaperPickerGesture()
        .accessibilityIdentifier("playlistView")
    }

    @ViewBuilder
    private func playlistRow(for entry: any PlaylistEntry) -> some View {
        switch entry {
        case let playcut as Playcut:
            PlaycutRowView(playcut: playcut)
            
        case let breakpoint as Breakpoint:
            TextRowView(text: breakpoint.formattedDate)
            
        case _ as Talkset:
            TextRowView(text: "Talkset")
            
        default:
            EmptyView()
        }
    }
}

#Preview {
    PlaylistView()
        .environment(Singletonia.shared)
        .environment(\.playlistService, PlaylistService())
        .background(WXYCBackground())
}
