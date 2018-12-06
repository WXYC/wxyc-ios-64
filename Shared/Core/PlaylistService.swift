//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit

public protocol PlaylistServiceObserver: class {
    func updateWith(playcutResult: Result<Playcut>)
    func updateWith(artworkResult: Result<UIImage>)
}

public final class PlaylistService {
    private let nowPlayingService: NowPlayingService
    private let artworkService: ArtworkService
    
    private let playcutRequest: Future<Playcut>
    private let artworkRequest: Future<UIImage>

    private let observers: [PlaylistServiceObserver]
    
    public convenience init(observers: PlaylistServiceObserver...) {
        self.init(service: NowPlayingService(), artworkService: ArtworkService(), initialObservers: observers)
    }
    
    init(service: NowPlayingService,
         artworkService: ArtworkService,
         initialObservers: [PlaylistServiceObserver]) {
        self.nowPlayingService = service
        self.artworkService = artworkService
        
        self.observers = initialObservers
        
        self.playcutRequest = Future.repeat(self.nowPlayingService.getCurrentPlaycut)
        self.artworkRequest = self.playcutRequest.chained(with: self.artworkService.getArtwork(for:))

        let playcutCallbacks = initialObservers.map { $0.updateWith(playcutResult:) }
        self.playcutRequest.observe(with: playcutCallbacks)
        
        let artworkCallbacks = initialObservers.map { $0.updateWith(artworkResult:) }
        self.artworkRequest.observe(with: artworkCallbacks)
    }
}
