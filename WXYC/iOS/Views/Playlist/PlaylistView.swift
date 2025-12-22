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
    @State private var longPressTask: Task<Void, Never>?
    @State private var isVerticalScrolling = false

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
                selectedPlayerType: $selectedPlayerType,
                wallpaperConfiguration: appState.wallpaperConfiguration
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    // Only track vertical drag (scrolling) to cancel long press
                    // Horizontal drags are for tab swiping - ignore them
                    let verticalDistance = abs(value.translation.height)
                    let horizontalDistance = abs(value.translation.width)

                    if verticalDistance > horizontalDistance {
                        isVerticalScrolling = true
                        longPressTask?.cancel()
                        longPressTask = nil
                    }
                }
                .onEnded { _ in
                    isVerticalScrolling = false
                }
        )
        .onLongPressGesture(minimumDuration: 1.0, pressing: { isPressing in
            if isPressing && !isVerticalScrolling {
                // Start long press timer
                longPressTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    enterWallpaperPicker()
                }
            } else {
                // Finger lifted - cancel pending action
                longPressTask?.cancel()
                longPressTask = nil
            }
        }, perform: {
            // Action handled in pressing callback via Task
        })
        .accessibilityIdentifier("playlistView")
    }

    private func enterWallpaperPicker() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            appState.wallpaperPickerState.enter(
                currentWallpaperID: appState.wallpaperConfiguration.selectedWallpaperID
            )
        }
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
