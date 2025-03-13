//
//  PlaylistPage.swift
//  WatchXYC App
//
//  Created by Jake Bromberg on 2/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Core
import Logger

@Observable
final class Playlister {
    var playlist: Playlist = .empty
    
    init() {
        Task { await self.observe() }
    }
    
    func observe() async {
        let playlistTask =
            withObservationTracking {
                Task { await PlaylistService.shared.playlist }
            } onChange: {
                Task { await self.observe() }
            }
        
        let playlist = await playlistTask.value
        
        if validateCollection(playlist.entries, label: "PlaylistPage entries") {
            self.playlist = await PlaylistService.shared.playlist
        } else {
            let waitTime = self.backoffTimer.nextWaitTime()
            Log(.info, "Playlist is empty. Now trying exponential backoff \(self.backoffTimer). Session duration: \(SessionStartTimer.duration())")
            try? await Task.sleep(nanoseconds: waitTime.nanoseconds)
            Task { await self.observe() }
        }
    }
    
    var backoffTimer = ExponentialBackoff()
}

struct PlaylistPage: View {
    @State var playlister = Playlister()
    
    var body: some View {
        List {
            Section("Recently Played") {
                ForEach(playlister.playlist.wrappedEntries) { wrappedEntry in
                    switch wrappedEntry {
                    case .playcut(let playcut):
                        PlaycutView(playcut: playcut)
                            .listRowInsets(EdgeInsets(10))
                    case .breakpoint(let breakpoint):
                        BreakpointView(breakpoint: breakpoint)
                            .listRowBackground(Color.black)
                    case .talkset(_):
                        TalksetView()
                            .background(
                            )
                            .listRowBackground(Color.black)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EdgeInsets {
    init(_ inset: CGFloat) {
        self.init(top: inset, leading: inset, bottom: inset, trailing: inset)
    }
}

struct PlaycutView: View {
    let playcut: Playcut
    
    init(playcut: Playcut) {
        self.playcut = playcut
        
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            RemoteImage(playcut: playcut)
                .cornerRadius(10)
                .frame(
                    width: 50,
                    height: 50
                )
            
            Text(playcut.songTitle)
                .font(.body)
                .fontWeight(.bold)
            Text(playcut.artistName)
                .font(.caption)
        }
    }
}

struct BreakpointView: View {
    let date: String
    
    init(breakpoint: Breakpoint) {
        self.date = breakpoint.formattedDate
    }
    
    var body: some View {
        Text("\(date)")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct TalksetView: View {
    var body: some View {
        Text("Talkset")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    PlaylistPage()
}
