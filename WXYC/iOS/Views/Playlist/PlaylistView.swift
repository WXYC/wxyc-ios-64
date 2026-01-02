//
//  PlaylistView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import UIKit
import WXUI
import AppIntents
import DebugPanel
import PlayerHeaderView
import PartyHorn
import Playlist
import PostHog
import Wallpaper

struct PlaycutSelection {
    let playcut: Playcut
    let artwork: UIImage?
}

struct PlaylistView: View {
    @State private var playlistEntries: [any PlaylistEntry] = []
    @Environment(\.playlistService) private var playlistService
    @Environment(\.isWallpaperPickerActive) private var isWallpaperPickerActive

    @State private var visualizer = VisualizerDataSource()
    @State private var selectedPlayerType = PlayerControllerType.loadPersisted()
    @State private var showVisualizerDebug = false
    @State private var showingPartyHorn = false
    @State private var showingSiriTip = false
    @State private var showingWallpaperTip = false

    @State private var selectedPlaycut: PlaycutSelection?

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

                // Wallpaper tip
                if showingWallpaperTip {
                    WallpaperTipView(isVisible: $showingWallpaperTip) {
                        WallpaperTipView.recordDismissal()
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
            .padding(.top, isWallpaperPickerActive ? 24 : 0)
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
            showingWallpaperTip = WallpaperTipView.shouldShow()
        }
        .task {
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                withAnimation {
                    self.playlistEntries = playlist.entries
                }
            }
        }
        .wallpaperPickerGesture(
            pickerState: appState.wallpaperPickerState,
            configuration: appState.wallpaperConfiguration
        )
        .accessibilityIdentifier("playlistView")
        .overlaySheet(isPresented: Binding(
            get: { selectedPlaycut != nil },
            set: { if !$0 { selectedPlaycut = nil } }
        )) {
            if let selection = selectedPlaycut {
                PlaycutDetailView(playcut: selection.playcut, artwork: selection.artwork)
            }
        }
    }

    @ViewBuilder
    private func playlistRow(for entry: any PlaylistEntry) -> some View {
        switch entry {
        case let playcut as Playcut:
            PlaycutRowView(playcut: playcut) { artwork in
                selectedPlaycut = PlaycutSelection(playcut: playcut, artwork: artwork)
            }

        case let breakpoint as Breakpoint:
            TextRowView(text: breakpoint.formattedDate)

        case _ as Talkset:
            TextRowView(text: "Talkset")

        case let showMarker as ShowMarker:
            TextRowView(text: showMarkerText(for: showMarker))

        default:
            EmptyView()
        }
    }

    private func showMarkerText(for marker: ShowMarker) -> String {
        if let djName = marker.djName {
            marker.isStart ? "\(djName) signed on" : "\(djName) signed off"
        } else {
            marker.isStart ? "Signed on" : "Signed off"
        }
    }
}

#Preview {
    PlaylistView()
        .environment(Singletonia.shared)
        .environment(\.playlistService, PlaylistService())
        .background(WXYCBackground())
}
