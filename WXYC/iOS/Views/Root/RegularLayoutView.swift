//
//  RegularLayoutView.swift
//  WXYC
//
//  NavigationSplitView-based layout for regular horizontal size class (iPad, Mac).
//  Sidebar shows the player header, playlist, and info actions. Detail column shows
//  the selected playcut or an empty-state placeholder.
//
//  Created by Jake Bromberg on 04/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppServices
import Artwork
import Playlist
import PlayerHeaderView
import SwiftUI
import UIKit
import Wallpaper
import WXUI

struct RegularLayoutView: View {
    @State private var selectedPlaycutID: Playcut.ID?
    @State private var playlistEntries: [any PlaylistEntry] = []
    @State private var visualizer = VisualizerDataSource()

    @Environment(\.playlistService) private var playlistService
    @Environment(\.isThemePickerActive) private var isThemePickerActive
    @Environment(\.themeAppearance) private var appearance
    @Environment(Singletonia.self) private var appState

    private var selectedPlaycut: Playcut? {
        Self.findPlaycut(id: selectedPlaycutID, in: playlistEntries)
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPlaycutID)
        #if targetEnvironment(macCatalyst)
        .onExitCommand {
            selectedPlaycutID = nil
        }
        #endif
        .task {
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                withAnimation {
                    self.playlistEntries = playlist.entries
                }
                // Clear stale selection
                if let id = selectedPlaycutID,
                   !playlist.entries.contains(where: { ($0 as? Playcut)?.id == id }) {
                    selectedPlaycutID = nil
                }
            }
        }
        .themePickerGesture(
            pickerState: appState.themePickerState,
            configuration: appState.themeConfiguration
        )
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
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

            List(selection: $selectedPlaycutID) {
                ForEach(Array(playlistEntries.enumerated()), id: \.element.id) { index, entry in
                    let playcutIndex = playcutIndex(for: index)

                    if playcutIndex == 0 {
                        PlaylistSectionHeader(text: "now playing")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else if playcutIndex == 1 {
                        PlaylistSectionHeader(text: "recently played")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    sidebarRow(for: entry)
                }

                SidebarInfoSection()
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func sidebarRow(for entry: any PlaylistEntry) -> some View {
        switch entry {
        case let playcut as Playcut:
            SidebarPlaycutRow(playcut: playcut)
                .tag(playcut.id)
                .listRowBackground(Color.clear)

        case let breakpoint as Breakpoint:
            Text(breakpoint.formattedDate.uppercased())
                .font(.caption.bold().smallCaps())
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

        case _ as Talkset:
            Text("Talkset".uppercased())
                .font(.caption.bold().smallCaps())
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

        case let showMarker as ShowMarker:
            Text(showMarkerText(for: showMarker).uppercased())
                .font(.caption.bold().smallCaps())
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

        default:
            EmptyView()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let playcut = selectedPlaycut {
            ScrollView {
                PlaycutDetailView(playcut: playcut, artwork: nil)
                    .id(playcut.id)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView(
                "Select a Track",
                systemImage: "music.note",
                description: Text("Choose a track from the playlist to see details")
            )
        }
    }

    // MARK: - Helpers

    /// Pure function for testability. Finds a playcut by ID in a list of playlist entries.
    static func findPlaycut(id: Playcut.ID?, in entries: [any PlaylistEntry]) -> Playcut? {
        guard let id else { return nil }
        return entries.compactMap { $0 as? Playcut }.first { $0.id == id }
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
