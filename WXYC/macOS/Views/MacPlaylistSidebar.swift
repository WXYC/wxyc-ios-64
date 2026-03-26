//
//  MacPlaylistSidebar.swift
//  WXYC
//
//  Sidebar view showing the player header and scrollable playlist. Selecting
//  a playcut updates the detail pane via the binding.
//
//  Created by Jake Bromberg on 03/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import PlayerHeaderView
import Playlist
import SwiftUI
import Wallpaper
import WXUI

struct MacPlaycutSelection: Identifiable, Equatable {
    let playcut: Playcut

    var id: UInt64 { playcut.id }

    static func == (lhs: MacPlaycutSelection, rhs: MacPlaycutSelection) -> Bool {
        lhs.playcut.id == rhs.playcut.id
    }
}

struct MacPlaylistSidebar: View {
    @Binding var selectedPlaycut: MacPlaycutSelection?

    @State private var playlistEntries: [any PlaylistEntry] = []
    @State private var visualizer = VisualizerDataSource()
    @Environment(\.playlistService) private var playlistService
    @Environment(\.isThemePickerActive) private var isThemePickerActive
    @Environment(\.themeAppearance) private var appearance

    var body: some View {
        ScrollView {
            PlayerHeaderView(
                visualizer: visualizer,
                onDebugTapped: {}
            )
            .lcdAccentColor(appearance.accentColor)
            .lcdHSBOffsets(
                min: appearance.lcdMinOffset,
                max: appearance.lcdMaxOffset
            )
            .lcdActiveBrightness(appearance.lcdActiveBrightness)

            LazyVStack(spacing: 0) {
                ForEach(Array(playlistEntries.enumerated()), id: \.element.id) { index, entry in
                    let playcutIndex = playcutIndex(for: index)

                    if playcutIndex == 0 {
                        PlaylistSectionHeader(text: "now playing")
                    } else if playcutIndex == 1 {
                        PlaylistSectionHeader(text: "recently played")
                    }

                    if let playcut = entry as? Playcut {
                        MacPlaylistRowView(playcut: playcut, isSelected: selectedPlaycut?.playcut.id == playcut.id)
                            .onTapGesture {
                                selectedPlaycut = MacPlaycutSelection(playcut: playcut)
                            }
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .task {
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                withAnimation {
                    self.playlistEntries = playlist.entries
                }
            }
        }
    }

    private func playcutIndex(for index: Int) -> Int? {
        guard playlistEntries[index] is Playcut else { return nil }
        return playlistEntries[..<index].filter { $0 is Playcut }.count
    }
}

struct PlaylistSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold).smallCaps())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
    }
}
