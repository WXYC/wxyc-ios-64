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

public struct NowPlayingItem: Sendable, Equatable, Comparable {
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
    
    public static func < (lhs: NowPlayingItem, rhs: NowPlayingItem) -> Bool {
        lhs.playcut.chronOrderID < rhs.playcut.chronOrderID
    }
}

@MainActor
@Observable
public final class NowPlayingService: @unchecked Sendable {
    public static let shared = NowPlayingService()
    
    @MainActor
    public private(set) var nowPlayingItem: NowPlayingItem? {
        didSet {
            for o in observers {
                o(self.nowPlayingItem)
            }
        }
    }
    
    public typealias Observer = @MainActor @Sendable (NowPlayingItem?) -> ()
    @MainActor private var observers: [Observer] = []
    
    @MainActor
    public func observe(_ observer: @escaping Observer) {
        Task { @MainActor in
            observer(self.nowPlayingItem)
            self.observers.append(observer)
        }
    }
    
    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    private var playlistServiceObservation: Sendable? = nil
    
    init(
        playlistService: PlaylistService = PlaylistService(),
        artworkService: ArtworkService = .shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        
        self.observePlaylistService()
    }
    
    var playcuts: [Playcut] = []
    
    @MainActor
    private func observePlaylistService() {
        PlaylistService.shared.observe { playlist in
            print(">>>>> playlist updated")
            self.handle(playlist: playlist)
        }
    }
    
    func handle(playlist: Playlist) {
        playcuts = playlist.playcuts
        
        guard let playcut = playlist.playcuts.first else {
            return
        }

        Task {
            let artwork = await self.artworkService.getArtwork(for: playcut)
            self.updateNowPlayingItem(
                nowPlayingItem: NowPlayingItem(playcut: playcut, artwork: artwork)
            )
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
