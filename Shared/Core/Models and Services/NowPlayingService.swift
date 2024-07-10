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
}

@Observable
public final class NowPlayingService: @unchecked Sendable {
    public static let shared = NowPlayingService()
    
    @ObservationTracked public private(set) var nowPlayingItem: NowPlayingItem? {
        get {
            return self.accessorQueue.sync { self._nowPlayingItem }
        }
        set {
            self.accessorQueue.sync { self._nowPlayingItem = newValue }
        }
    }
    @ObservationIgnored private(set) var _nowPlayingItem: NowPlayingItem? = nil
    @ObservationIgnored private let accessorQueue = DispatchQueue(label: "NowPlayingService")
    
    @ObservationIgnored private let playlistService: PlaylistService
    @ObservationIgnored private let artworkService: ArtworkService
    @ObservationIgnored private var playlistObservation: Sendable? = nil
    
    init(
        playlistService: PlaylistService = PlaylistService(),
        artworkService: ArtworkService = .shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        
        self.playlistObservation = withObservationTracking {
            self.playlistService.playlist.playcuts
        } onChange: {
            Task {
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
