//
//  PlaycutService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit
import Logger
import Observation

public struct NowPlayingItem: Sendable, Equatable {
    public let playcut: Playcut
    public var artwork: UIImage?
    
    public init(playcut: Playcut, artwork: UIImage? = nil) {
        self.playcut = playcut
        self.artwork = artwork
    }
    
    public static func ==(lhs: NowPlayingItem, rhs: NowPlayingItem) -> Bool {
        lhs.playcut == rhs.playcut
        && lhs.artwork == rhs.artwork
    }
}

@MainActor @Observable
public final class NowPlayingService: @unchecked Sendable {
    public static let shared = NowPlayingService()
    
    public private(set) var nowPlayingItem: NowPlayingItem?
    
    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    private var playlistServiceObservation: Sendable? = nil
    
    init(
        playlistService: PlaylistService = PlaylistService(),
        artworkService: ArtworkService = .shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        self.observe()
    }
    
    private func observe() {
        let playlist =
            withObservationTracking {
                PlaylistService.shared.playlist
            } onChange: {
                Task { @MainActor in
                    self.observe()
                }
            }
        
        if validateCollection(playlist.entries, label: "NowPlayingService entries"),
           let playcut = playlist.playcuts.first {
            Task {
                let artwork = await self.artworkService.getArtwork(for: playcut)
                self.updateNowPlayingItem(
                    nowPlayingItem: NowPlayingItem(playcut: playcut, artwork: artwork)
                )
            }
        } else {
            Log(.info, "Playlist is empty. Now trying exponential backoff. Session duration: \(SessionStartTimer.duration())")
            Task { @MainActor in
                let nanoseconds = self.backoffTimer.nextWaitTime().nanoseconds
                Task {
                    try await Task.sleep(nanoseconds: nanoseconds)
                    self.observe()
                }
            }
        }
    }
    
    var backoffTimer = ExponentialBackoff()
    
    private func updateNowPlayingItem(nowPlayingItem: NowPlayingItem) {
        guard self.nowPlayingItem != nowPlayingItem else {
            Log(.info, "No change in nowPlayingItem")
            return
        }
        Log(.info, "Setting nowPlayingItem \(nowPlayingItem)")
        self.nowPlayingItem = nowPlayingItem
    }
    
    public func fetch() async -> NowPlayingItem? {
        guard let playcut = await self.playlistService.fetchPlaylist(forceSync: true).playcuts.first else {
            Log(.info, "No playcut found in fetched playlist")
            return nil
        }
        let artwork = await self.artworkService.getArtwork(for: playcut)
        return NowPlayingItem(playcut: playcut, artwork: artwork)
    }
}
