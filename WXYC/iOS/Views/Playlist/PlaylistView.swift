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
    @Environment(\.isThemePickerActive) private var isThemePickerActive

    @State private var visualizer = VisualizerDataSource()
    @State private var selectedPlayerType = PlayerControllerType.loadPersisted()
    @State private var showVisualizerDebug = false
    @State private var showingPartyHorn = false
    @State private var showingSiriTip = false
    @State private var showingThemeTip = false

    @State private var selectedPlaycut: PlaycutSelection?

    @Environment(Singletonia.self) var appState

    private var currentMaterial: Material {
        let themeID = appState.themeConfiguration.selectedThemeID
        let theme = ThemeRegistry.shared.theme(for: themeID)
        return theme?.manifest.materialWeight.material ?? .thinMaterial
    }
            
    var body: some View {
        @Bindable var appState = appState
        
        ZStack {
            Color.clear
            
            ScrollView(showsIndicators: false) {
                PlayerHeaderView(
                    visualizer: visualizer,
                    selectedPlayerType: $selectedPlayerType,
                    material: currentMaterial,
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

                // Theme tip
                if showingThemeTip {
                    ThemeTipView(isVisible: $showingThemeTip) {
                        ThemeTipView.recordDismissal()
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
            .padding(.top, isThemePickerActive ? 24 : 0)
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
            showingThemeTip = ThemeTipView.shouldShow()
        }
        .task {
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                withAnimation {
                    self.playlistEntries = playlist.entries
                }
            }
        }
        .themePickerGesture(
            pickerState: appState.themePickerState,
            configuration: appState.themeConfiguration
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
