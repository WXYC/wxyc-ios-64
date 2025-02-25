//
//  PlaycutService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit

public struct NowPlayingItem: Sendable {
    public let playcut: Playcut
    public var artwork: UIImage?
    
    public init(playcut: Playcut, artwork: UIImage? = nil) {
        self.playcut = playcut
        self.artwork = artwork
    }
}

@MainActor
public final class NowPlayingService: @unchecked Sendable {
    public static let shared = NowPlayingService()
    
    @Publishable public private(set) var nowPlayingItem: NowPlayingItem?
    
    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    private var playlistServiceObservation: Sendable? = nil
    
    init(
        playlistService: PlaylistService = PlaylistService(),
        artworkService: ArtworkService = .shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        
        let _ = self.playlistService.$playlist
        
        self.playlistService.$playlist.observe { playlist in
            guard let playcut = self.playlistService.playlist.playcuts.first else {
                return
            }
            
            let artwork = await self.artworkService.getArtwork(for: playcut)
            await self.updateNowPlayingItem(nowPlayingItem: NowPlayingItem(playcut: playcut, artwork: artwork))
        }
    }
    
    private func updateNowPlayingItem(nowPlayingItem: NowPlayingItem) {
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
