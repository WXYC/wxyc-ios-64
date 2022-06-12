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

public struct NowPlayingItem {
    public let playcut: Playcut
    public var artwork: UIImage?
}

public final class NowPlayingService: ObservableObject {
    public static let shared = NowPlayingService()
    
    // TODO: remove this observe stuff
    public let nowPlayingObservable = PassthroughSubject<NowPlayingItem, Never>()
    
    public func observe(_ sink: @escaping (NowPlayingItem) -> Void)  -> AnyCancellable {
        return self.nowPlayingObservable.sink(receiveValue: sink)
    }
    
    @Published public var nowPlayingItem: NowPlayingItem? = nil
    private var playcut: Playcut? = nil {
        didSet {
            guard oldValue?.id != self.playcut?.id, let playcut = self.playcut else {
                return
            }

            DispatchQueue.main.async {
                Task {
                    let artwork = await self.artworkService.getArtwork(for: playcut)
                    self.nowPlayingItem = NowPlayingItem(playcut: playcut, artwork: artwork)
                    self.nowPlayingObservable.send(NowPlayingItem(playcut: playcut, artwork: artwork))
                }
            }
        }
    }
    
    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    private var timer: Timer?
    
    private var playcutObservation: Cancellable? = nil

    internal init(
        playlistService: PlaylistService = .shared,
        artworkService: ArtworkService = .shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        
        self.playcutObservation = self.playlistService
            .$playlist
            .compactMap(\.playcuts.first)
            .map(Optional.init)
            .receive(on: RunLoop.main)
            .assign(to: \.playcut, on: self)
    }
    
    public func fetch() async -> NowPlayingItem? {
        guard let playcut = await self.playlistService.fetchPlaylist(forceSync: true).playcuts.first else {
            return nil
        }
        let artwork = await self.artworkService.getArtwork(for: playcut)
        return NowPlayingItem(playcut: playcut, artwork: artwork)
    }
}
