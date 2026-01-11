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
    @Binding var selectedPlaycut: PlaycutSelection?

    @State private var playlistEntries: [any PlaylistEntry] = []
    @Environment(\.playlistService) private var playlistService
    @Environment(\.isThemePickerActive) private var isThemePickerActive
    @Environment(\.currentAccentHue) private var currentAccentHue
    @Environment(\.currentAccentSaturation) private var currentAccentSaturation
    @Environment(\.currentAccentBrightness) private var currentAccentBrightness
    @Environment(\.currentLCDMinBrightness) private var currentLCDMinBrightness
    @Environment(\.currentLCDMaxBrightness) private var currentLCDMaxBrightness

    @State private var visualizer = VisualizerDataSource()
    @State private var selectedPlayerType = PlayerControllerType.loadPersisted()
    @State private var showVisualizerDebug = false
    @State private var showingPartyHorn = false
    @State private var showingSiriTip = false
    @State private var showingThemeTip = false

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
                .lcdAccentColor(
                    hue: currentAccentHue,
                    saturation: currentAccentSaturation,
                    brightness: currentAccentBrightness
                )
                .lcdBrightness(
                    min: currentLCDMinBrightness,
                    max: currentLCDMaxBrightness
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
                        appState.themePickerState.recordTipDismissedByUser()
                    }
                    .padding(.vertical, 8)
                }

                // Playlist entries
                LazyVStack(spacing: 0) {
                    ForEach(Array(playlistEntries.enumerated()), id: \.element.id) { index, entry in
                        let playcutIndex = playcutIndex(for: index)

                        if playcutIndex == 0 {
                            PlaylistSectionHeader(text: "now playing")
                        } else if playcutIndex == 1 {
                            PlaylistSectionHeader(text: "recently played")
                        }

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
                        .foregroundStyle(AnimatedMeshGradient())
                        .padding(.top, 20)
                        .padding(.bottom, 20)
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
                selectedPlayerType: $selectedPlayerType,
                onResetThemePickerState: {
                    appState.themePickerState.persistence.resetState()
                },
                onResetSiriTip: {
                    SiriTipView.resetState()
                }
            )
            .presentationDetents([.fraction(0.75)])
        }
        #endif
        .onAppear {
            showingSiriTip = SiriTipView.recordLaunchAndShouldShow()
            showingThemeTip = appState.themePickerState.persistence.shouldShowTip
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

    /// Returns the playcut index (0-based) if the entry at the given index is a Playcut, or nil otherwise.
    private func playcutIndex(for index: Int) -> Int? {
        guard playlistEntries[index] is Playcut else { return nil }
        return playlistEntries[..<index].filter { $0 is Playcut }.count
    }
}

struct PlaylistSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold).smallCaps())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 16)
    }
}

#Preview {
    PlaylistView(selectedPlaycut: .constant(nil))
        .environment(Singletonia.shared)
        .environment(\.playlistService, PlaylistService())
        .background(WXYCBackground())
}
