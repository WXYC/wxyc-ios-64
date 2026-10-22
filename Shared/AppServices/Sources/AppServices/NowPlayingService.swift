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
    /// A specialty show with no song yet leads.
    case specialty(SpecialtyShowRef)
    /// A freeform show with no song yet leads; carries the DJ's handle.
    case dj(String)
    /// Nothing leads: automation, or no song and no on-air information.
    case nothing
    /// The playlist could not be read in time (a timeout or a failed fetch), so nothing is known.
    case unavailable

    /// The sentence to speak for this answer. The one place the copy for each answer lives.
    public var spokenDialog: String {
        switch self {
        case .song(let item):
            "\(item.playcut.songTitle) by \(item.playcut.artistName) is now playing on WXYC."
        case .specialty(let show):
            ["\(show.name) is on the air on WXYC.", show.tagline].compactMap { $0 }.joined(separator: " ")
        case .dj(let handle):
            "\(handle) is on the air on WXYC."
        case .nothing:
            "Nothing is playing on WXYC right now."
        case .unavailable:
            "Can't reach WXYC right now. Try again in a moment."
        }
    }
}

/// Why ``NowPlayingService/currentAnswer(timeout:)`` gave up waiting.
private struct NowPlayingAnswerTimeout: Error {}

public final actor NowPlayingService: Sendable, AsyncSequence {
    public typealias Element = NowPlayingItem

    private let playlistService: PlaylistService
    private let artworkService: ArtworkService
    private let errorReporter: any ErrorReporter

    public init(
        playlistService: PlaylistService,
        artworkService: ArtworkService,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.playlistService = playlistService
        self.artworkService = artworkService
        self.errorReporter = errorReporter
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
    /// Fetches the playlist once, keeping a failure distinct from an empty playlist, and answers
    /// from ``Playlist/nowPlayingLead``. The whole call, playlist and artwork, is bounded by
    /// `timeout`. A timeout or a failed fetch answers ``NowPlayingAnswer/unavailable`` and
    /// reports the error; it is never answered as ``NowPlayingAnswer/nothing``.
    public func currentAnswer(timeout: Duration = .seconds(8)) async -> NowPlayingAnswer {
        let answer = await withTaskGroup(of: NowPlayingAnswer?.self) { group in
            group.addTask { await self.fetchAnswer() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let answer else {
            errorReporter.report(NowPlayingAnswerTimeout(), context: "NowPlayingService currentAnswer")
            return .unavailable
        }
        return answer
    }

    private func fetchAnswer() async -> NowPlayingAnswer {
        switch await playlistService.fetchPlaylistResult() {
        case .failure(let error):
            // Cancelled because the timeout won: that path reports the timeout itself.
            if !Task.isCancelled {
                errorReporter.report(error, context: "NowPlayingService currentAnswer")
            }
            return .unavailable
        case .success(let playlist):
            switch playlist.nowPlayingLead {
            case .song(let playcut):
                return .song(await item(for: playcut))
            case .specialtyCard(let show):
                return .specialty(show)
            case .djHandle(let handle):
                return .dj(handle)
            case .nothing:
                return .nothing
            }
        }
    }
}
