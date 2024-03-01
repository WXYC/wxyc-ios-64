//
//  PlaycutService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit

public struct NowPlayingItem {
    public let playcut: Playcut
    public var artwork: UIImage?
}

@Observable
public final class NowPlayingService {
    public static let shared = NowPlayingService()
    
    public private(set) var nowPlayingItem: NowPlayingItem? = nil
    
    @ObservationIgnored private let playlistService: PlaylistService
    @ObservationIgnored private let artworkService: ArtworkService
    @ObservationIgnored private var playlistObservation: Any? = nil
    @ObservationIgnored private var updateTask: Any? = nil
    
    internal init(
        playlistService: PlaylistService = .shared,
        artworkService: ArtworkService = .shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        
        self.playlistObservation = withObservationTracking { @MainActor in
            Task { @MainActor in
                self.playlistService.playlist.playcuts
            }
        } onChange: {
            Task { @MainActor in
                guard let playcut = self.playlistService.playlist.playcuts.first else {
                    return
                }

                let artwork = await self.artworkService.getArtwork(for: playcut)
                self.nowPlayingItem = NowPlayingItem(playcut: playcut, artwork: artwork)
            }
        }
    }
    
    public func fetch() async -> NowPlayingItem? {
        guard let playcut = await self.playlistService.fetchPlaylist(forceSync: true).playcuts.first else {
            return nil
        }
        let artwork = await self.artworkService.getArtwork(for: playcut)
        return NowPlayingItem(playcut: playcut, artwork: artwork)
    }
}
