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

/// The `{ playcut, artwork }` pair for a resolved playcut. The iOS app's
/// flowsheet selection state composes this type (adding a zoom-transition
/// identity) rather than re-declaring the same two fields — see #408. Keep this
/// the single declaration of that shape.
///
/// Note the `Equatable` conformance below is the artwork-refresh one: it compares
/// the image, so an enrichment that only fills in artwork reads as a new value.
/// Composers that need a different identity declare their own `==` rather than
/// inheriting this one.
public struct NowPlayingItem: Sendable, Equatable, Comparable {
    public let playcut: Playcut
    public var artwork: Image?

    public init(playcut: Playcut, artwork: Image? = nil) {
        self.playcut = playcut
        self.artwork = artwork
    }

    // A deliberate asymmetry with `<` below: equality includes `artwork` so
    // an enrichment that only changes the image still reads as a new value
    // (and re-renders), while ordering ignores it — artwork carries no
    // position. Strictly this bends the Comparable contract (two items with
    // the same playcut but different artwork are unequal yet mutually
    // non-ordered); it is harmless today because playcuts are deduped by id
    // upstream of every sort, making such pairs unreachable, and `sort`
    // treats non-ordered pairs as tie-equivalent. Don't "fix" `==` to match
    // `<` without an artwork-refresh story.
    public static func ==(lhs: NowPlayingItem, rhs: NowPlayingItem) -> Bool {
        lhs.playcut == rhs.playcut
        && lhs.artwork == rhs.artwork
    }

    public static func < (lhs: NowPlayingItem, rhs: NowPlayingItem) -> Bool {
        // Delegates to `Playcut`'s own `Comparable` (chronOrderID, then id as
        // an explicit tiebreak — see `PlaylistEntry`'s default `<`) rather
        // than re-deriving the comparison here, so the two can't drift.
        lhs.playcut < rhs.playcut
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
            // Skip playlists with no playcuts (e.g. talkset-only shows)
            while true {
                guard let playlist = await playlistStream.next() else {
                    return nil
                }

                guard let playcut = playlist.currentPlaycut else {
                    Log(.info, "No playcut found in playlist, waiting for next update")
                    continue
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
}
