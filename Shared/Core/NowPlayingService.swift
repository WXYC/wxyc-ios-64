//
//  PlaycutService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit

public protocol NowPlayingServiceObserver: class {
    func updateWith(playcutResult: Result<Playcut>)
    func updateWith(artworkResult: Result<UIImage>)
}

public final class NowPlayingService {
    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    
    private let playcutRequest: Future<Playcut>
    private let artworkRequest: Future<UIImage>

    private let observers: [NowPlayingServiceObserver]
    
    public convenience init(observers: NowPlayingServiceObserver...) {
        self.init(playlistService: PlaylistService(), artworkService: ArtworkService.shared, initialObservers: observers)
    }
    
    init(playlistService: PlaylistService,
         artworkService: ArtworkService,
         initialObservers: [NowPlayingServiceObserver]) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        
        self.observers = initialObservers
        
        self.playcutRequest = self.playlistService.getPlaylist().transformed { playlist in
            return playlist.playcuts.first
        }
        
        self.artworkRequest = self.playcutRequest.chained(with: self.artworkService.getArtwork(for:))

        let playcutCallbacks = initialObservers.map { $0.updateWith(playcutResult:) }
        self.playcutRequest.observe(with: playcutCallbacks)
        
        let artworkCallbacks = initialObservers.map { $0.updateWith(artworkResult:) }
        self.artworkRequest.observe(with: artworkCallbacks)
    }
}
