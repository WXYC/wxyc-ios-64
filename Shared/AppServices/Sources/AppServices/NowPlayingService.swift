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

/// The answer to a one-shot "what's playing" question. See ``NowPlayingService/currentAnswer(timeout:)``.
public enum NowPlayingAnswer: Sendable, Equatable {
    /// A song leads.
    case song(NowPlayingItem)
    /// Something other than a song leads: a specialty card, a DJ handle, or nothing.
    /// Never ``NowPlayingLead/song(_:)``.
    case lead(NowPlayingLead)

    /// The sentence to speak for this answer.
    public var spokenDialog: String {
        switch self {
        case .song(let item):
            "\(item.playcut.songTitle) by \(item.playcut.artistName) is now playing on WXYC."
        case .lead(.specialtyCard(let show)):
            "\(show.name) is on the air on WXYC."
        case .lead(.djHandle(let name)):
            "\(name) is on the air on WXYC."
        case .lead(.song), .lead(.none):
            "Nothing is playing on WXYC right now."
        }
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

                return await service.item(for: playcut)
            }
        }
    }

    /// Fetches the artwork for `playcut`; a failed fetch yields an item with no artwork.
    func item(for playcut: Playcut) async -> NowPlayingItem {
        let artwork: Image?
        do {
            let cgImage = try await artworkService.fetchArtwork(for: playcut)
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

    /// One prompt answer to "what's playing", for callers (the Siri/Shortcuts intent) that
    /// cannot wait on the stream: the iterator suspends until a song leads, which never
    /// happens during automation or before a new show's first song.
    ///
    /// Reads the first playlist the service has and answers from ``Playlist/nowPlayingLead``:
    /// the leading song with its artwork, or the specialty card, DJ handle, or nothing. If no
    /// playlist arrives within `timeout`, the answer is nothing.
    public func currentAnswer(timeout: Duration = .seconds(8)) async -> NowPlayingAnswer {
        let service = playlistService
        let playlist: Playlist? = await withTaskGroup(of: Playlist?.self) { group in
            group.addTask {
                var iterator = service.updates().makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let playlist else {
            return .lead(.none)
        }
        switch playlist.nowPlayingLead {
        case .song(let playcut):
            return .song(await item(for: playcut))
        case let lead:
            return .lead(lead)
        }
    }
}
