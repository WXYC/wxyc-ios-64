//
//  PlaycutService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit
import Combine

public protocol NowPlayingServiceObserver: AnyObject {
    func update(playcut: Playcut?)
    func update(artwork: UIImage?)
}

public final class NowPlayingService {
    public static let shared = NowPlayingService()
    
    @Published public var playcut: Playcut? = nil {
        didSet {
            guard let playcut = playcut else {
                self.artwork = nil
                return
            }
            
            Task {
                do {
                    self.artwork = try await self.artworkService.getArtwork(for: playcut)
                } catch {
                    self.artwork = nil
                }
            }
        }
    }
    @Published public var artwork: UIImage? = nil

    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    
    private var playcutObservation: Cancellable? = nil

    init(
        playlistService: PlaylistService = .shared,
        artworkService: ArtworkService = .shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        
        let playcutRequest = self.playlistService
            .$playlist
            .map(\.playcuts.first)
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
        
        self.playcutObservation = playcutRequest
            .assign(to: \.playcut, on: self)
    }
    
    public func observe(with observer: NowPlayingServiceObserver) -> Any {
        return (
            self.$playcut.sink(receiveValue: observer.update(playcut:)),
            self.$artwork.sink(receiveValue: observer.update(artwork:))
        )
    }
}
