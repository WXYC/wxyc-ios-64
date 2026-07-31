//
//  PlaycutMetadataService.swift
//  Metadata
//
//  Service for fetching and caching extended playcut metadata via backend proxy.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Artwork
import Logger
import Core
import Caching
import Playlist
import WXYCAPIModels

// MARK: - CriticReviewItemWire conformance

/// Lets the generated proxy DTO feed straight into `CriticReview.validated(_:)`
/// / `CriticReview.parsed(from:)` (`Playlist`) without a field-by-field
/// adapter — `WXYCAPIModels.CriticReviewItem` already has exactly the wire
/// shape `CriticReviewItemWire` describes (`source`, `url`, `snippet`,
/// `author`, `publishedDate`, `rating`). Declared here, not in `WXYCAPIModels`
/// or `Playlist`: the generated model can't depend on `Playlist` (wrong
/// dependency direction), and `Playlist` doesn't depend on `WXYCAPIModels` in
/// its shipping target (see `docs/code-generation.md`) — `Metadata` is the
/// one package that already imports both.
extension WXYCAPIModels.CriticReviewItem: @retroactive CriticReviewItemWire {}

// MARK: - PlaycutMetadataService

/// Service for fetching extended metadata about a playcut from the backend proxy.
///
/// Uses multi-level caching to reduce redundant API calls:
/// - Artist metadata is cached by Discogs artist ID (30-day TTL)
/// - Album metadata is cached by artist+release key (7-day TTL)
/// - Streaming links are cached by artist+song key (7-day TTL when populated,
///   ``emptyStreamingLifespan`` when every streaming URL came back nil)
public actor PlaycutMetadataService {
    /// Short TTL applied to streaming-cache entries that came back with every
    /// URL nil. Long enough to absorb back-to-back views of the same playcut
    /// within an iOS session without re-hitting the proxy, short enough that a
    /// freshly-enriched row (BS read-path or LML reconciliation landing the
    /// streaming URL minutes later) supersedes the empty entry rather than
    /// being shadowed for a week.
    static let emptyStreamingLifespan: TimeInterval = 15 * 60

    private let baseURL: URL
    private let tokenProvider: SessionTokenProvider?
    private let session: WebSession
    private let urlSession: URLSession
    private let cache: CacheCoordinator
    private let errorReporter: any ErrorReporter

    public init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = URLSession.shared
        self.urlSession = .shared
        self.cache = .Metadata
        self.errorReporter = errorReporter
    }

    // Internal initializer for testing
    init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        session: WebSession,
        urlSession: URLSession = .shared,
        cache: CacheCoordinator = .Metadata,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.urlSession = urlSession
        self.cache = cache
        self.errorReporter = errorReporter
    }

    /// Fetches all available metadata for a playcut using granular caching.
    ///
    /// This method caches at three levels:
    /// - Album metadata by artist+release (7-day TTL)
    /// - Artist metadata by Discogs artist ID (30-day TTL)
    /// - Streaming links by artist+song (7-day TTL when populated,
    ///   ``emptyStreamingLifespan`` when every URL came back nil)
    public func fetchMetadata(for playcut: Playcut) async -> PlaycutMetadata {
        await fetchMetadata(for: playcut, inline: nil)
    }

    /// Fetches metadata, optionally seeded by an inline V2 flowsheet row.
    ///
    /// When `inline` is non-nil, the inline metadata is returned directly with
    /// no network call whenever the row's `metadataStatus` is terminal
    /// (`enrichedMatch`/`enrichedNoMatch`/`failedNoRetry` — Backend has already
    /// given up or finished enrichment, so a proxy round-trip can't add
    /// anything, even when inline streaming is sparse or empty; see #685) or
    /// when `inline` already carries at least one streaming URL. When the
    /// inline row exists but every streaming URL is nil and the status isn't
    /// terminal (Tragic Magic shape — the V2 writer landed the artwork/Discogs
    /// columns but no streaming side, mid-enrichment), the service falls
    /// through to `/proxy/metadata/album` so the BS read path can fill the
    /// streaming gap. Inline album- and artist-level fields are preserved when
    /// the proxy omits them.
    ///
    /// Deliberate tradeoff: the terminal short-circuit means a terminal row
    /// with no streaming links no longer falls through to the proxy, so it
    /// also gives up whatever the proxy alone can supply — `discogsArtistId`,
    /// `fullReleaseDate` (`AlbumMetadata`), and pre-parsed `bioTokens`
    /// (`ArtistMetadata`) — none of which the V2 flowsheet row carries. This
    /// is accepted as the cost of never spending a degradable LML round-trip
    /// on a row Backend already gave up on (#685); Backend-Service#1827
    /// ("assemble base metadata before enrichment") is meant to narrow this
    /// gap by ensuring terminal rows carry richer inline data before they're
    /// marked terminal.
    ///
    /// `criticReviews` used to be on this casualty list too, but isn't
    /// anymore (#695): the V2 flowsheet feed now carries `critic_reviews`
    /// inline, `FlowsheetConverter` threads it onto `Playcut.criticReviews`,
    /// and `PlaycutDetailView.loadMetadata()` folds it into the inline
    /// `AlbumMetadata` it builds — so a terminal row's reviews survive the
    /// short-circuit without ever touching the proxy.
    ///
    /// - Parameters:
    ///   - playcut: The playcut to resolve metadata for.
    ///   - inline: Optional inline metadata constructed from the V2 flowsheet
    ///     response. Pass `nil` to behave like the V1 path.
    public func fetchMetadata(for playcut: Playcut, inline: PlaycutMetadata?) async -> PlaycutMetadata {
        // The `metadataStatus?.isTerminal` check here is intentionally NOT
        // simplified to "trust hasV2Metadata already decided this" — this is a
        // public actor API and `inline` could in principle come from any
        // caller, not just `PlaycutDetailView`. Keeping the terminal check
        // independent of `inline`'s shape means Gate 2 stays correct even if a
        // future caller builds `inline` differently than `hasV2Metadata`
        // (`Shared/Playlist/Sources/Playlist/PlaylistEntry.swift`) does.
        if let inline, playcut.metadataStatus?.isTerminal == true || inline.streaming.hasAny {
            return inline
        }

        // Either no inline metadata at all, or inline-but-empty-streaming.
        // In both cases we want the proxy fetch so the BS read path can
        // contribute streaming URLs that the inline V2 write path missed.
        let (album, streaming) = await fetchAlbumAndStreaming(for: playcut)

        // Artist metadata requires the Discogs artist ID from the album lookup
        let artist = await fetchArtistMetadata(discogsArtistId: album.discogsArtistId)

        guard let inline else {
            return PlaycutMetadata(artist: artist, album: album, streaming: streaming)
        }

        // Inline fallthrough: prefer the proxy result where present, else fall
        // back to the inline values. This protects inline album fields (label,
        // releaseYear) and the inline artist bio when the proxy returns only
        // streaming URLs.
        return PlaycutMetadata(
            artist: artist == .empty ? inline.artist : artist,
            album: Self.mergeAlbum(proxy: album, inline: inline.album),
            streaming: streaming
        )
    }

    /// Coalesces two `AlbumMetadata` records field-by-field, preferring `proxy`
    /// values where present and falling back to `inline` otherwise. Used on the
    /// V2 fallthrough path so inline album fields the proxy didn't refresh
    /// (label, releaseYear, artworkURL on the LML synth-shape) survive.
    private static func mergeAlbum(proxy: AlbumMetadata, inline: AlbumMetadata) -> AlbumMetadata {
        AlbumMetadata(
            label: proxy.label ?? inline.label,
            releaseYear: proxy.releaseYear ?? inline.releaseYear,
            discogsURL: proxy.discogsURL ?? inline.discogsURL,
            discogsArtistId: proxy.discogsArtistId ?? inline.discogsArtistId,
            genres: proxy.genres ?? inline.genres,
            styles: proxy.styles ?? inline.styles,
            fullReleaseDate: proxy.fullReleaseDate ?? inline.fullReleaseDate,
            artworkURL: proxy.artworkURL ?? inline.artworkURL,
            criticReviews: proxy.criticReviews ?? inline.criticReviews,
            // `proxy.discogsUnavailable` is always nil today — the proxy fetch
            // below can't populate it (see the comment there) — so this falls
            // back to whatever the inline V2 row carried. Still written as a
            // `??` merge, not a straight `inline.discogsUnavailable`, so this
            // starts working automatically the day the proxy gap closes.
            discogsUnavailable: proxy.discogsUnavailable ?? inline.discogsUnavailable,
            discogsUnavailableNote: proxy.discogsUnavailableNote ?? inline.discogsUnavailableNote
        )
    }

    /// Maps served critic-review items into domain `CriticReview`s, applying
    /// `CriticReview.validated(_:)`'s URL-validation policy (Playlist package)
    /// so the mandatory link-out guarantee (ADR 0012) holds. Returns `nil` when
    /// nothing was served, when the served array is empty, or when every item
    /// was dropped for a bad URL — the domain preserves "no reviews attached"
    /// vs. "empty after filtering" as an equivalent `nil`, avoiding caching a
    /// pointless empty array.
    ///
    /// A thin wrapper, not a duplicate: the actual policy lives once in
    /// `CriticReview.parsed(from:)`, reused verbatim by the V2 flowsheet feed's
    /// inline `critic_reviews` decode (`FlowsheetEntry`/`TolerantCriticReviewItem`,
    /// #695) via the same `CriticReviewItemWire` conformance point.
    private static func mapCriticReviews(_ dtos: [WXYCAPIModels.CriticReviewItem]?) -> [CriticReview]? {
        CriticReview.parsed(from: dtos)
    }

    // MARK: - Granular Caching Methods

    /// Fetches artist metadata, caching by Discogs artist ID.
    private func fetchArtistMetadata(discogsArtistId: Int?) async -> ArtistMetadata {
        guard let artistId = discogsArtistId else {
            return .empty
        }

        let cacheKey = MetadataCacheKey.artist(discogsId: artistId)

        return (try? await cachedFetch(
            key: cacheKey,
            cache: cache,
            lifespan: .thirtyDays,
            fetch: {
                let response = try await fetchFromProxy(
                    path: "proxy/metadata/artist",
                    queryItems: [URLQueryItem(name: "artistId", value: String(artistId))]
                )
                return try JSONDecoder.shared.decode(WXYCAPIModels.ArtistMetadataResponse.self, from: response)
            },
            transform: { apiResult in
                ArtistMetadata(
                    bio: apiResult.bio,
                    bioTokens: apiResult.bioTokens?.compactMap(ResolvedBioToken.init),
                    wikipediaURL: apiResult.wikipediaUrl.flatMap { URL(string: $0) },
                    discogsArtistId: apiResult.discogsArtistId ?? artistId
                )
            }
        )) ?? .empty
    }

    /// Fetches album metadata and streaming links from the backend proxy in a single call.
    ///
    /// Deliberately not refactored onto `cachedFetch`: one network response feeds two
    /// caches with different keys (`.album(artist, release)` and `.streaming(artist, song)`),
    /// and a partial cache hit on either side must still issue the fetch but only write the
    /// missing side. The existing single-key `cachedFetch` overloads can't model that without
    /// a bespoke 2-cache variant, and this is the only caller that would need it. See #192.
    private func fetchAlbumAndStreaming(for playcut: Playcut) async -> (AlbumMetadata, StreamingLinks) {
        let albumCacheKey = MetadataCacheKey.album(
            artistName: playcut.artistName,
            releaseTitle: playcut.releaseTitle ?? ""
        )
        let streamingCacheKey = MetadataCacheKey.streaming(
            artistName: playcut.artistName,
            songTitle: playcut.songTitle
        )

        // Check both caches
        let cachedAlbum: AlbumMetadata? = try? await cache.value(for: albumCacheKey)
        let cachedStreaming: StreamingLinks? = try? await cache.value(for: streamingCacheKey)

        if let album = cachedAlbum, let streaming = cachedStreaming {
            Log(.info, category: .network, "Album+streaming cache hit for \(playcut.artistName)")
            return (album, streaming)
        }

        let fallbackAlbum = cachedAlbum ?? AlbumMetadata(label: playcut.labelName)
        let fallbackStreaming = cachedStreaming ?? .empty

        return await timedOperation(
            context: "fetchAlbumAndStreaming(\(playcut.artistName))",
            category: .network,
            fallback: (fallbackAlbum, fallbackStreaming),
            errorReporter: errorReporter
        ) {
            var queryItems = [URLQueryItem(name: "artistName", value: playcut.artistName)]
            if let releaseTitle = playcut.releaseTitle {
                let title = releaseTitle.lowercased() == "s/t" ? playcut.artistName : releaseTitle
                queryItems.append(URLQueryItem(name: "releaseTitle", value: title))
            }
            queryItems.append(URLQueryItem(name: "trackTitle", value: playcut.songTitle))

            let data = try await fetchFromProxy(path: "proxy/metadata/album", queryItems: queryItems)
            let apiResult = try JSONDecoder.shared.decode(WXYCAPIModels.AlbumMetadataResponse.self, from: data)

            // NOTE (#390): `apiResult.discogsUnavailable` doesn't exist — BS
            // already emits `discogsUnavailable`/`discogsUnavailableNote` on
            // this same `/proxy/metadata/album` response (BS#1901), but
            // `WXYCAPIModels.AlbumMetadataResponse` doesn't declare the field:
            // wxyc-shared's `api.yaml` only added the trio to the `Album`
            // schema, not `AlbumMetadataResponse`. Decoding straight into the
            // generated type is deliberate here (see docs/code-generation.md
            // "Drift guards-of-record") — it's not worked around with a
            // parallel hand-decode. `album.discogsUnavailable` below is left
            // at its default `nil` until a wxyc-shared contract fix adds the
            // field and this repo regenerates.
            let album = cachedAlbum ?? AlbumMetadata(
                label: apiResult.label ?? playcut.labelName,
                releaseYear: apiResult.releaseYear,
                discogsURL: apiResult.discogsUrl.flatMap { URL(string: $0) },
                discogsArtistId: apiResult.discogsArtistId,
                genres: apiResult.genres,
                styles: apiResult.styles,
                fullReleaseDate: apiResult.fullReleaseDate,
                artworkURL: apiResult.artworkUrl.flatMap { URL(string: $0) },
                criticReviews: Self.mapCriticReviews(apiResult.criticReviews)
            )

            let streaming = cachedStreaming ?? StreamingLinks(
                spotifyURL: apiResult.spotifyUrl.flatMap { URL(string: $0) },
                appleMusicURL: apiResult.appleMusicUrl.flatMap { URL(string: $0) },
                youtubeMusicURL: apiResult.youtubeMusicUrl.flatMap { URL(string: $0) },
                bandcampURL: apiResult.bandcampUrl.flatMap { URL(string: $0) },
                soundcloudURL: apiResult.soundcloudUrl.flatMap { URL(string: $0) }
            )

            if cachedAlbum == nil {
                await cache.set(value: album, for: albumCacheKey, lifespan: .sevenDays)
            }
            if cachedStreaming == nil {
                // Short-TTL on empty-streaming entries so a freshly-enriched row
                // supersedes within the same iOS session rather than being shadowed
                // for a week (#303).
                let streamingLifespan: TimeInterval = streaming.hasAny ? .sevenDays : Self.emptyStreamingLifespan
                await cache.set(value: streaming, for: streamingCacheKey, lifespan: streamingLifespan)
            }

            return (album, streaming)
        }
    }

    // MARK: - Network

    private func fetchFromProxy(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems

        guard let url = components.url else {
            throw MetadataError.invalidURL
        }

        if let tokenProvider {
            let request = URLRequest(url: url)
            let (data, _) = try await urlSession.authedData(for: request, tokenProvider: tokenProvider)
            return data
        } else {
            return try await session.data(from: url)
        }
    }
}

// MARK: - Errors

extension PlaycutMetadataService {
    enum MetadataError: Error {
        case invalidURL
    }
}
