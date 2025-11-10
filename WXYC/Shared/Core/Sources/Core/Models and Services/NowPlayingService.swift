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

public final actor NowPlayingService: Sendable, AsyncSequence {
    public typealias Element = NowPlayingItem

    private let playlistService: PlaylistService
    private let artworkFetcher: ArtworkFetcher

    public init(
        playlistService: PlaylistService,
        artworkService: ArtworkFetcher
    ) {
        self.playlistService = playlistService
        self.artworkFetcher = artworkService
    }

    public nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(service: self)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let service: NowPlayingService
        private var playlistIterator: PlaylistService.AsyncIterator

        init(service: NowPlayingService) {
            self.service = service
            self.playlistIterator = service.playlistService.makeAsyncIterator()
        }

        public mutating func next() async throws -> NowPlayingItem? {
            // Get the next playlist
            guard let playlist = await playlistIterator.next() else {
                return nil
            }

            // Get the first playcut
            guard let playcut = playlist.playcuts.first else {
                Log(.info, "No playcut found in playlist")
                // Continue to next playlist
                return try await next()
            }

            // Fetch artwork for the playcut
            let artwork = try await service.artworkFetcher.fetchArtwork(for: playcut)
            return NowPlayingItem(playcut: playcut, artwork: artwork)
        }
    }

    /// Fetch a single now playing item immediately without iterating
    public func fetchOnce() async throws -> NowPlayingItem? {
        let playlist = await playlistService.fetchPlaylist()
        guard let playcut = playlist.playcuts.first else {
            Log(.info, "No playcut found in fetched playlist")
            return nil
        }
        let artwork = try await artworkFetcher.fetchArtwork(for: playcut)
        return NowPlayingItem(playcut: playcut, artwork: artwork)
    }
}
