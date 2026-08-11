//
//  PlaycutMetadataService.swift
//  Metadata
//
//  Service for fetching and caching extended playcut metadata via backend proxy.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//
//  The proxy request/decode pipeline is now a thin wrapper over
//  `Core.WXYCProxyClient` (#761): the single `urlSession` field replaces the
//  former dual `WebSession`/`URLSession` fields this type carried solely to
//  branch on whether a token provider existed — `WXYCProxyClient` (via
//  `URLSession.authedData(for:tokenProvider:)`) already sends a plain
//  unauthenticated request when `tokenProvider` is `nil`, so that branch was
//  never needed. `MetadataError.invalidURL` is gone too; that case is now
//  `WXYCProxyClient.ProxyError.invalidURL`.
//

import Foundation
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
/// - Album metadata is cached by artist+release key (7-day TTL when it carries
///   enrichment, ``sparseAlbumLifespan`` when it doesn't)
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

    /// Short TTL applied to album-cache entries that came back with no
    /// enrichment output at all (``AlbumMetadata/isSparse``) *for a row whose
    /// `metadataStatus` says Backend is still enriching it*.
    ///
    /// Decision recorded for #812: the album side gets the same treatment #303
    /// gave the streaming side, rather than no-cache. A row is served by the
    /// feed for roughly two seconds before its enrichment lands, and the proxy
    /// has nothing to say about it during that window; pinning that answer for
    /// seven days meant a card sampled in the window stayed blank even after
    /// closing and reopening it — the durable half of the bug. Short-TTL beats
    /// not caching at all because the sparse answer still absorbs back-to-back
    /// views within a session without re-hitting a proxy that would only
    /// return the same nothing. Deliberately a separate constant from
    /// ``emptyStreamingLifespan`` despite the equal value: the two answer to
    /// different upstreams (BS enrichment vs. LML streaming reconciliation)
    /// and should be tunable apart.
    ///
    /// Scoped to mid-enrichment rows rather than to the payload shape alone —
    /// see the gate in ``fetchAlbumAndStreaming(for:)`` for why a permanently
    /// unmatched row must not land here.
    static let sparseAlbumLifespan: TimeInterval = 15 * 60

    /// Bounded backoff delays between `/proxy/metadata/album` retry attempts
    /// on a transient failure (#284) — 3 total attempts (the initial try plus
    /// these 2 delays), not the 4-attempt/100ms-500ms-2.5s schedule the
    /// ticket sketches: a 3-attempt budget only has 2 gaps to fill, and
    /// spending all 3 delays (3.1s of sleeping before the request latency
    /// itself) would breach the ticket's own "≤3s aggregate" UI-tap-latency
    /// acceptance criterion. 100ms + 500ms = 600ms of sleeping stays
    /// comfortably inside that budget.
    private static let albumFetchRetryDelays: [Duration] = [.milliseconds(100), .milliseconds(500)]

    private let client: WXYCProxyClient
    private let cache: CacheCoordinator
    private let errorReporter: any ErrorReporter

    /// In-flight `/proxy/metadata/album` fetches, keyed by the exact query
    /// they share (#282). See ``fetchAlbumAndStreaming(for:)`` for the
    /// coalescing contract and ``pendingAlbumFetchKey(for:)`` for why the key
    /// must be as specific as the query itself.
    private var pendingAlbumAndStreamingFetches: [String: Task<(AlbumMetadata, StreamingLinks), Never>] = [:]

    /// In-flight `/proxy/metadata/artist` fetches, keyed by Discogs artist ID
    /// (#282). Safe to coalesce purely on the artist ID — unlike the album
    /// fetch, this endpoint's answer depends on nothing else the caller
    /// supplies.
    private var pendingArtistFetches: [Int: Task<ArtistMetadata, Never>] = [:]

    public init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.client = WXYCProxyClient(baseURL: baseURL, tokenProvider: tokenProvider)
        self.cache = .Metadata
        self.errorReporter = errorReporter
    }

    // Internal initializer for testing
    init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        urlSession: URLSession = .shared,
        cache: CacheCoordinator = .Metadata,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.client = WXYCProxyClient(baseURL: baseURL, session: urlSession, tokenProvider: tokenProvider)
        self.cache = cache
        self.errorReporter = errorReporter
    }

    /// Fetches all available metadata for a playcut using granular caching.
    ///
    /// This method caches at three levels:
    /// - Album metadata by artist+release (7-day TTL when it carries
    ///   enrichment, ``sparseAlbumLifespan`` when it doesn't)
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
    /// and ``PlaycutMetadataResolver/inlineMetadata(for:)`` folds it into the
    /// inline `AlbumMetadata` it builds — so a terminal row's reviews survive
    /// the short-circuit without ever touching the proxy.
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

        // Inline fallthrough. Both records coalesce field-by-field: proxy
        // preferred, inline filling the gaps, so inline fields the proxy didn't
        // refresh (label, releaseYear, artworkURL on the LML synth-shape,
        // `artistBio`) survive a response that carried only streaming URLs — and
        // `discogsUnavailable` takes the proxy's answer when the BS read path
        // resolved it (BS#1901), falling back to the inline V2 row when the
        // response omits it (e.g. a cache hit predating the field).
        //
        // The artist side used to be a whole-record `artist == .empty` test,
        // which could never choose the inline side once the album lookup had
        // resolved a `discogsArtistId`: `fetchArtistMetadata` writes that id into
        // the record unconditionally, so a bio-less proxy answer is non-empty and
        // silently replaced whatever bio the V2 row carried. Same coalescer the
        // detail card's enrichment repair uses (#812); see
        // ``AlbumMetadata/coalescing(over:)``.
        return PlaycutMetadata(
            artist: artist.coalescing(over: inline.artist),
            album: album.coalescing(over: inline.album),
            streaming: streaming
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
    ///
    /// Coalesces concurrent calls for the same `artistId` (#282): the first
    /// caller starts the work, a concurrent caller for the same ID awaits
    /// that same in-flight `Task` instead of issuing its own request. See
    /// ``fetchAlbumAndStreaming(for:)`` for the shared correctness argument
    /// (actor-isolated dict access, independent unstructured `Task`, `defer`
    /// clears the entry so the coalescing window is the in-flight duration
    /// only).
    private func fetchArtistMetadata(discogsArtistId: Int?) async -> ArtistMetadata {
        guard let artistId = discogsArtistId else {
            return .empty
        }

        if let existingTask = pendingArtistFetches[artistId] {
            return await existingTask.value
        }

        let task = Task<ArtistMetadata, Never> {
            defer { Task { await self.clearPendingArtistFetch(for: artistId) } }
            return await self.fetchArtistMetadataUncoalesced(artistId: artistId)
        }
        pendingArtistFetches[artistId] = task
        return await task.value
    }

    private func clearPendingArtistFetch(for artistId: Int) {
        pendingArtistFetches[artistId] = nil
    }

    private func fetchArtistMetadataUncoalesced(artistId: Int) async -> ArtistMetadata {
        let cacheKey = MetadataCacheKey.artist(discogsId: artistId)

        return (try? await cachedFetch(
            key: cacheKey,
            cache: cache,
            lifespan: .thirtyDays,
            fetch: {
                let response: WXYCAPIModels.ArtistMetadataResponse = try await client.get(
                    "proxy/metadata/artist",
                    query: [URLQueryItem(name: "artistId", value: String(artistId))]
                )
                return response
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

    /// Coalesces concurrent `/proxy/metadata/album` fetches for the same
    /// exact query (#282): the first caller for a key starts the work,
    /// concurrent callers for the same key await that same in-flight `Task`
    /// instead of issuing their own request.
    ///
    /// Correctness relies on actor isolation, not manual locking: the
    /// dict-check-then-store below has no `await` between the check and the
    /// write, so two calls that look "concurrent" from the caller's
    /// perspective are strictly serialized onto this actor — the second can
    /// never run its own check until the first has either returned (an
    /// existing task was found) or stored its new `Task` in the dict.
    ///
    /// The shared `Task` is created independently of any caller's own `Task`
    /// (a plain `Task { }`, not a structured child), so cancelling one
    /// caller's enclosing `Task` has no effect on the shared fetch or on any
    /// other caller awaiting it. The `defer` inside the `Task` clears the
    /// dict entry the moment the fetch finishes — success or failure — so
    /// the coalescing window is the in-flight duration only: a call that
    /// arrives after completion always re-enters ``fetchAlbumAndStreamingUncoalesced(for:)``,
    /// which re-checks the (possibly now-populated) TTL cache, rather than
    /// reusing a stale finished `Task` forever.
    private func fetchAlbumAndStreaming(for playcut: Playcut) async -> (AlbumMetadata, StreamingLinks) {
        let pendingKey = Self.pendingAlbumFetchKey(for: playcut)

        if let existingTask = pendingAlbumAndStreamingFetches[pendingKey] {
            return await existingTask.value
        }

        let task = Task<(AlbumMetadata, StreamingLinks), Never> {
            defer { Task { await self.clearPendingAlbumFetch(for: pendingKey) } }
            return await self.fetchAlbumAndStreamingUncoalesced(for: playcut)
        }
        pendingAlbumAndStreamingFetches[pendingKey] = task
        return await task.value
    }

    private func clearPendingAlbumFetch(for key: String) {
        pendingAlbumAndStreamingFetches[key] = nil
    }

    /// The coalescing key for ``fetchAlbumAndStreaming(for:)`` — the
    /// concatenation of the two cache keys a single fetch populates.
    ///
    /// Deliberately as specific as the query itself (artist + release +
    /// **track**), not merely artist + release: the streaming-link fields
    /// are resolved per track (`trackTitle` is a query parameter precisely
    /// because streaming URLs differ per song), so two different songs on
    /// the same album are different requests and must not share one answer —
    /// coalescing on album alone would risk handing one track's streaming
    /// links to a different track's cache entry.
    private static func pendingAlbumFetchKey(for playcut: Playcut) -> String {
        MetadataCacheKey.album(artistName: playcut.artistName, releaseTitle: playcut.releaseTitle ?? "")
            + "|"
            + MetadataCacheKey.streaming(artistName: playcut.artistName, songTitle: playcut.songTitle)
    }

    // MARK: - Repair write-back (#821)

    /// Writes the album metadata the detail card's enrichment repair (#812)
    /// resolved for `playcut` back into the album cache, merging over
    /// whatever's already cached rather than replacing it.
    ///
    /// The repair path (`PlaycutMetadataResolver.repairs(for:playlists:)`)
    /// takes ``fetchMetadata(for:inline:)``'s terminal short-circuit, so its
    /// only source of an album is the inline V2 flowsheet row — never the
    /// proxy (#685's zero-request budget on a terminal row must stay
    /// structural, not conditional; this method only touches the cache,
    /// never `client`). That inline album is missing exactly the two fields
    /// only `/proxy/metadata/album` supplies — `discogsArtistId` and
    /// `fullReleaseDate` (see ``fetchMetadata(for:inline:)``'s doc comment
    /// for the full #685 casualty list). Writing it verbatim would downgrade
    /// an already-cached proxy answer, and — because `discogsArtistId` is
    /// load-bearing, not decorative — worse than that: `fetchArtistMetadata`
    /// returns `.empty` when it's `nil`, so an album cached without it denies
    /// artist bio to any later read that hits this entry.
    ///
    /// `AlbumMetadata.coalescing(over:)` makes the merge monotonic: a field
    /// the cached record already has survives regardless of what the repair
    /// carries. Reuses #814's merge rather than hand-rolling a second one.
    ///
    /// The TTL answers a narrower question than the proxy-fetch gate in
    /// ``fetchAlbumAndStreamingUncoalesced(for:)``: not "is this sparse" (a
    /// repaired album from a terminal row's inline fields usually isn't — it
    /// typically carries `releaseYear`/`artworkURL`/`genres`) but "does the
    /// merged record still lack `discogsArtistId`". A merged record without
    /// one gets ``sparseAlbumLifespan`` — the same 15-minute bound #812 gives
    /// a mid-enrichment sparse answer — so a bio-less window can't outlive
    /// that; one that already carries `discogsArtistId` (from the repair
    /// itself, or preserved from what was already cached) keeps the normal
    /// `.sevenDays`.
    ///
    /// Skips the write entirely when the merge produces nothing the cache
    /// didn't already have, so a repair that can't improve the cached answer
    /// doesn't reset its TTL clock for no reason.
    func cacheRepairedAlbum(_ repaired: AlbumMetadata, for playcut: Playcut) async {
        let albumCacheKey = MetadataCacheKey.album(
            artistName: playcut.artistName,
            releaseTitle: playcut.releaseTitle ?? ""
        )
        let cachedAlbum: AlbumMetadata? = try? await cache.value(for: albumCacheKey)
        let merged = repaired.coalescing(over: cachedAlbum ?? .empty)

        if let cachedAlbum, merged == cachedAlbum {
            return
        }

        let lifespan: TimeInterval = merged.discogsArtistId == nil
            ? Self.sparseAlbumLifespan
            : .sevenDays
        await cache.set(value: merged, for: albumCacheKey, lifespan: lifespan)
    }

    /// Fetches album metadata and streaming links from the backend proxy in a single call.
    ///
    /// Deliberately not refactored onto `cachedFetch`: one network response feeds two
    /// caches with different keys (`.album(artist, release)` and `.streaming(artist, song)`),
    /// and a partial cache hit on either side must still issue the fetch but only write the
    /// missing side. The existing single-key `cachedFetch` overloads can't model that without
    /// a bespoke 2-cache variant, and this is the only caller that would need it. See #192.
    private func fetchAlbumAndStreamingUncoalesced(for playcut: Playcut) async -> (AlbumMetadata, StreamingLinks) {
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

            let apiResult = try await fetchAlbumWithRetry(query: queryItems)

            // BS emits `discogsUnavailable`/`discogsUnavailableNote` on this
            // response (BS#1901), and `WXYCAPIModels.AlbumMetadataResponse`
            // declares the field (#731 closed the wxyc-shared/api.yaml +
            // codegen gap, see docs/code-generation.md "Drift guards-of-
            // record"), so it decodes straight into `apiResult` and flows
            // through here — no parallel hand-decode needed.
            let album = cachedAlbum ?? AlbumMetadata(
                label: apiResult.label ?? playcut.labelName,
                releaseYear: apiResult.releaseYear,
                discogsURL: apiResult.discogsUrl.flatMap { URL(string: $0) },
                discogsArtistId: apiResult.discogsArtistId,
                genres: apiResult.genres,
                styles: apiResult.styles,
                fullReleaseDate: apiResult.fullReleaseDate,
                artworkURL: apiResult.artworkUrl.flatMap { URL(string: $0) },
                criticReviews: Self.mapCriticReviews(apiResult.criticReviews),
                discogsUnavailable: apiResult.discogsUnavailable,
                discogsUnavailableNote: apiResult.discogsUnavailableNote
            )

            let streaming = cachedStreaming ?? StreamingLinks(
                spotifyURL: apiResult.spotifyUrl.flatMap { URL(string: $0) },
                appleMusicURL: apiResult.appleMusicUrl.flatMap { URL(string: $0) },
                youtubeMusicURL: apiResult.youtubeMusicUrl.flatMap { URL(string: $0) },
                bandcampURL: apiResult.bandcampUrl.flatMap { URL(string: $0) },
                soundcloudURL: apiResult.soundcloudUrl.flatMap { URL(string: $0) }
            )

            if cachedAlbum == nil {
                // Short-TTL on albums that came back with no enrichment output
                // *while the row says enrichment is still in flight*, so a card
                // sampled during the pre-enrichment window isn't shadowed by that
                // answer for a week (#812) — the album-side counterpart of the
                // empty-streaming rule below (#303).
                //
                // Both halves are load-bearing. The payload test alone would put
                // the whole never-matching cohort on a 15-minute TTL: a free-text
                // play that never linked to a catalog album produces the same
                // sparse shape *permanently*, so every card open past the TTL
                // would re-issue the round-trip and get back the same nothing —
                // a standing cost against LML for rows that can't improve. The
                // row's own lifecycle is what separates "not yet" from "never":
                // `pending`/`enriching` is Backend telling us this answer is
                // temporary. `nil` (v1 rows, free-text plays) and the terminal
                // states are not, and keep the long TTL.
                let midEnrichment = playcut.metadataStatus.map { !$0.isTerminal } ?? false
                let albumLifespan: TimeInterval = album.isSparse && midEnrichment
                    ? Self.sparseAlbumLifespan
                    : .sevenDays
                await cache.set(value: album, for: albumCacheKey, lifespan: albumLifespan)
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

    // MARK: - Transient-vs-permanent classification (#284)

    /// Fetches `/proxy/metadata/album`, retrying a transient failure (5xx,
    /// networking blip) with bounded backoff, and treating a permanent
    /// failure (404, or any other non-retryable error) as a definitive "no
    /// match" rather than an error.
    ///
    /// A permanent failure resolves to `WXYCAPIModels.AlbumMetadataResponse()`
    /// — the same all-nil shape a literal 200-with-empty-body response
    /// decodes to — so the caller's existing ``AlbumMetadata/isSparse``/
    /// mid-enrichment TTL gate (#812) is the only place that decides how long
    /// either answer is trusted, with no second negative-cache code path to
    /// keep in sync.
    ///
    /// Never retries cancellation: if the caller's own `Task` is cancelled
    /// (e.g. the detail card was dismissed mid-fetch), that must propagate
    /// immediately so `timedOperation`'s cancellation handling — not this
    /// retry loop — decides what happens next.
    ///
    /// - Throws: the last transient error, once ``albumFetchRetryDelays`` is
    ///   exhausted, so the caller's existing uncached fallback path is taken
    ///   rather than pinning a negative verdict for a condition that might
    ///   clear on the very next poll; or a cancellation error, immediately
    ///   and without retrying.
    private func fetchAlbumWithRetry(
        query: [URLQueryItem],
        remainingDelays: ArraySlice<Duration> = PlaycutMetadataService.albumFetchRetryDelays[...]
    ) async throws -> WXYCAPIModels.AlbumMetadataResponse {
        do {
            return try await client.get("proxy/metadata/album", query: query)
        } catch {
            if isCancellation(error) {
                throw error
            }
            guard Self.isTransient(error) else {
                // Permanent: no match, not a retry candidate.
                return WXYCAPIModels.AlbumMetadataResponse()
            }
            guard let delay = remainingDelays.first else {
                // Retries exhausted and still transient — propagate uncached.
                throw error
            }
            Log(.warning, category: .network, "Transient /proxy/metadata/album failure, retrying in \(delay): \(error)")
            try? await Task.sleep(for: delay)
            return try await fetchAlbumWithRetry(query: query, remainingDelays: remainingDelays.dropFirst())
        }
    }

    /// Whether `error` represents a transient condition worth retrying,
    /// rather than a definitive answer.
    ///
    /// Mirrors `Artwork.MultisourceArtworkService.isTransient` (#207) — same
    /// concept, same name, deliberately not a parallel taxonomy — applied
    /// here to decide whether to retry rather than whether to skip a
    /// negative-cache write (this fetch's existing `timedOperation` fallback
    /// path already never writes to cache on any thrown error; see
    /// ``fetchAlbumWithRetry(query:remainingDelays:)``).
    ///
    /// Deliberately excludes `URLError.cancelled`, unlike the artwork
    /// classifier: a cancelled request must propagate immediately so the
    /// caller's own cancellation handling runs, not be treated as "retry
    /// me" — `fetchAlbumWithRetry` checks for cancellation before this
    /// predicate is ever consulted.
    private static func isTransient(_ error: any Error) -> Bool {
        if let httpError = error as? HTTPStatusError {
            return (500...599).contains(httpError.statusCode)
        }
        guard let urlError = error as? URLError else { return false }
        return switch urlError.code {
        case .badServerResponse,
             .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed,
             .cannotConnectToHost,
             .cannotFindHost,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed:
            true
        default:
            false
        }
    }
}
