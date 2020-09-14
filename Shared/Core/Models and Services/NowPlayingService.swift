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

public protocol NowPlayingServiceObserver: class {
    func update(playcut: Playcut?)
    func update(artwork: UIImage?)
}

public final class NowPlayingService {
    public static let shared = NowPlayingService()
    
    @Published private var playcut: Playcut? = nil
    @Published private var artwork: UIImage? = nil

    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    
    private var playcutObservation: Cancellable? = nil
    private var artworkObservation: Cancellable? = nil

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
        
        self.artworkObservation = playcutRequest
            .map(self.artworkService.getArtwork(for:))
            .receive(on: RunLoop.main)
            .assign(to: \.artwork, on: self)
        
    }
    
    public func subscribe(_ observer: NowPlayingServiceObserver) -> Cancellable {
        return AnyCancellable.Combine(
            self.$artwork.sink(receiveValue: observer.update(artwork:)),
            self.$playcut.sink(receiveValue: observer.update(playcut:))
        )
    }
}

extension Publisher {
    func map<Wrapped, Mapped>(_ transform: @escaping (Wrapped) -> AnyPublisher<Mapped, Error>)
        -> AnyPublisher<Mapped?, Never>
        where Self.Output == Optional<Wrapped>
    {
        return self
            .tryMap(Self.Output.unwrap)
            .flatMap(transform)
            .map(Optional.init)
            .catch { _ in Just<Mapped?>(nil) }
            .eraseToAnyPublisher()
    }
}

extension Optional {
    static func unwrap(optional: Optional) throws -> Wrapped {
        guard case .some(let wrapped) = optional else {
            throw NSError()
        }
        
        return wrapped
    }
}
