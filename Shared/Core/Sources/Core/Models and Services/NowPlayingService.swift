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

public struct NowPlayingItem: Sendable {
    public let playcut: Playcut
    public var artwork: UIImage?
    
    public init(playcut: Playcut, artwork: UIImage? = nil) {
        self.playcut = playcut
        self.artwork = artwork
    }
}

let SessionStartTime = Date.now.timeIntervalSince1970

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
        self.playlistServiceObservation =
            withObservationTracking {
                self.playlistService.playlist
            } onChange: {
                Task {
                    Log(.info, "playlist updated")
                    guard let playcut = self.playlistService.playlist.playcuts.first else {
                        Log(.info, "Playlist is empty. Session duration: \(Date.now.timeIntervalSince1970 - SessionStartTime)")

                        return
                    }
                    
                    let artwork = await self.artworkService.getArtwork(for: playcut)
                    await self.updateNowPlayingItem(
                        nowPlayingItem: NowPlayingItem(playcut: playcut, artwork: artwork)
                    )
                    await self.observe()
                }
            }
    }
    
    private func updateNowPlayingItem(nowPlayingItem: NowPlayingItem) {
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
