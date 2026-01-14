//
//  NowPlayingService.swift
//  AppServices
//
//  Combines playlist and artwork services to provide NowPlayingItem updates.
//  Exposes an AsyncSequence that yields items with fetched artwork.
//
//  Created by Jake Bromberg on 12/03/17.
//  Copyright © 2017 WXYC. All rights reserved.
//

import Foundation
import Logger
import Playlist
import Artwork
import Core
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct NowPlayingItem: Sendable, Equatable, Comparable {
    public let playcut: Playcut
    public var artwork: Image?

    public init(playcut: Playcut, artwork: Image? = nil) {
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
    private let artworkService: ArtworkService

    public init(
        playlistService: PlaylistService,
        artworkService: ArtworkService
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
    }

    public nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(service: self)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let service: NowPlayingService
        private var playlistStream: AsyncStream<Playlist>.Iterator

        init(service: NowPlayingService) {
            self.service = service
            self.playlistStream = service.playlistService.updates().makeAsyncIterator()
        }

        public mutating func next() async throws -> NowPlayingItem? {
            // Get the next playlist
            guard let playlist = await playlistStream.next() else {
                return nil
            }

            // Get the first playcut
            guard let playcut = playlist.playcuts.first else {
                Log(.info, "No playcut found in playlist")
                // Continue to next playlist
                return try await next()
            }

            // Fetch artwork for the playcut
            let artwork: Image?
            do {
                let cgImage = try await service.artworkService.fetchArtwork(for: playcut)
                #if canImport(UIKit)
                artwork = UIImage(cgImage: cgImage)
                #else
                artwork = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                #endif
            } catch {
                Log(.warning, "Artwork fetch failed for playcut \(playcut.id): \(error)")
                artwork = nil
            }
            return NowPlayingItem(playcut: playcut, artwork: artwork)
        }
    }
}
