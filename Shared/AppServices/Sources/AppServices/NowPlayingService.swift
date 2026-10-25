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
    /// A who's-on entry leads; `program` is the specialty show's name, or `nil` on a freeform show.
    case spotlight(SpotlightEntry, program: String?)
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
        case .spotlight(let entry, let program):
            Self.spokenSpotlight(entry, program: program)
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

extension NowPlayingAnswer {
    /// The approved sentence for a who's-on lead: the person first on a freeform show, the program first on a
    /// specialty show. An unknown role gets the neutral wording.
    fileprivate static func spokenSpotlight(_ entry: SpotlightEntry, program: String?) -> String {
        let activity = entry.spokenActivity
        if let program {
            return "\(program) on WXYC, with \(entry.name)" + (activity.map { " \($0)" } ?? "") + "."
        }
        return "\(entry.name) " + (activity.map { "is \($0) on WXYC." } ?? "is on WXYC.")
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

                // A who's-on entry newer than the song leads: `NowPlayingInfoCenterManager.handleLead`
                // writes it, and the song must not overwrite it until the next one lands.
                if case .spotlight = playlist.nowPlayingLead {
                    continue
                }

                guard let playcut = playlist.currentPlaycut else {
                    Log(.info, "No playcut found in playlist, waiting for next update")
                    continue
                }

                let item = await service.item(for: playcut)

                // The artwork fetch can outlast a who's-on entry that took the lead meanwhile, and
                // that playlist is still queued behind this song. Check again so the song does not
                // overwrite the entry after the fact.
                if case .spotlight = await service.playlistService.currentPlaylistSnapshot().nowPlayingLead {
                    continue
                }

                return item
            }
        }
    }

    /// Fetches the artwork for `playcut`; a failed fetch yields an item with no artwork.
    public func item(for playcut: Playcut) async -> NowPlayingItem {
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
    /// `timeout`, even when a fetch ignores cancellation. If the playlist is not read in time, or
    /// the fetch fails, the answer is ``NowPlayingAnswer/unavailable``; it is never
    /// ``NowPlayingAnswer/nothing``. A timeout is reported here, but a cancelled caller is not; a failed fetch
    /// is already reported by the fetcher. If a song leads but its artwork is not ready in time, the answer is that
    /// song with no artwork.
    public func currentAnswer(timeout: Duration = .seconds(8)) async -> NowPlayingAnswer {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        let result = await Self.race(timeout: timeout) { await self.playlistService.fetchPlaylistResult() }
        guard let result else {
            // A cancelled caller (Siri dismissed) also ends the race early; that is not a timeout.
            if !Task.isCancelled {
                errorReporter.report(NowPlayingAnswerTimeout(), context: "NowPlayingService currentAnswer")
            }
            return .unavailable
        }
        guard case .success(let playlist) = result else {
            return .unavailable
        }

        switch playlist.nowPlayingLead {
        case .song(let playcut):
            let item = await Self.race(timeout: clock.now.duration(to: deadline)) { await self.item(for: playcut) }
            return .song(item ?? NowPlayingItem(playcut: playcut))
        case .spotlight(let entry):
            // `nowPlayingLead` only leads with an entry that has a role line (never a host row).
            var program: String?
            if case .dj(_, let show?) = playlist.onAir { program = show.specialty?.name }
            return .spotlight(entry, program: program)
        case .specialtyCard(let show):
            return .specialty(show)
        case .djHandle(let handle):
            return .dj(handle)
        case .nothing:
            return .nothing
        }
    }

    /// Runs `operation` and returns its value, or `nil` once `timeout` passes. Unlike a task group,
    /// it returns at the deadline even when `operation` ignores cancellation, which the artwork
    /// service's unstructured fetch does; that fetch is cancelled and left to finish on its own.
    private static func race<T: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        let (outcomes, continuation) = AsyncStream.makeStream(of: T?.self)
        let work = Task {
            continuation.yield(await operation())
            continuation.finish()
        }
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            continuation.yield(nil)
            continuation.finish()
        }
        defer {
            work.cancel()
            timer.cancel()
        }
        for await outcome in outcomes {
            return outcome
        }
        return nil
    }
}
