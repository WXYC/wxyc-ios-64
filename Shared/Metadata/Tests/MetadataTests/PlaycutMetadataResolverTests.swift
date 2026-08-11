//
//  PlaycutMetadataResolverTests.swift
//  Metadata
//
//  Tests for the playcut detail card's metadata resolution: the two-source
//  accumulator that makes arrival order irrelevant, the inline-vs-proxy
//  decision, and the enrichment repair that fixes a card opened before its
//  row finished enriching (#812).
//
//  Created by Jake Bromberg on 08/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//
//  The suites here that need a live `PlaycutMetadataService` are declared as an
//  `extension` of `PlaycutMetadataServiceHTTPTests` rather than as a suite of
//  their own. `CoreTesting.QueuedStubURLProtocol` registers by class, so its
//  header doc allows at most one adopting suite per test bundle and directs
//  further adopters to extend the existing one — the same arrangement
//  `DiscogsAPIEntityResolverCachingTests.swift` uses. Everything above that
//  extension is pure and touches no `URLSession` at all.
//

import Testing
import Foundation
import Core
import CoreTesting
import Playlist
import PlaylistTesting
@testable import Caching
@testable import Metadata

// MARK: - Fixtures

/// The flowsheet row as it is served during the ~2s pre-enrichment window:
/// real and renderable, but carrying only its base columns. `labelName` is the
/// one populated field, which is exactly why the stuck card renders the record
/// label and nothing else (#812).
private func enrichingRow(id: UInt64 = 5305276) -> Playcut {
    Playcut(
        id: id,
        hour: 1000,
        chronOrderID: id,
        timeCreated: 1000,
        songTitle: "Crawl",
        labelName: "Houndstooth",
        artistName: "Djrum",
        releaseTitle: "Meaning's Edge",
        metadataStatus: .enriching
    )
}

/// The same row two seconds later, after Backend's enrichment worker landed
/// `album_metadata` and flipped `metadata_status`.
private func enrichedRow(id: UInt64 = 5305276) -> Playcut {
    Playcut(
        id: id,
        hour: 1000,
        chronOrderID: id,
        timeCreated: 1000,
        songTitle: "Crawl",
        labelName: "Houndstooth",
        artistName: "Djrum",
        releaseTitle: "Meaning's Edge",
        artworkURL: URL(string: "https://i.discogs.com/meanings-edge.jpg"),
        discogsURL: URL(string: "https://www.discogs.com/release/30000001"),
        releaseYear: 2024,
        spotifyURL: URL(string: "https://open.spotify.com/track/crawl"),
        artistBio: "British electronic producer Felix Manuel.",
        genres: ["Electronic"],
        styles: ["Breakbeat", "Ambient"],
        metadataStatus: .enrichedMatch
    )
}

/// The row landing as `enrichedNoMatch`: LML found no Discogs release, so only
/// the synthesized search URLs are populated. Terminal, and strictly poorer
/// than what a successful proxy fetch can return — the shape that made a
/// wholesale replacement downgrade the card.
private func noMatchRow(id: UInt64 = 5305276) -> Playcut {
    Playcut(
        id: id,
        hour: 1000,
        chronOrderID: id,
        timeCreated: 1000,
        songTitle: "Crawl",
        labelName: "Houndstooth",
        artistName: "Djrum",
        releaseTitle: "Meaning's Edge",
        youtubeMusicURL: URL(string: "https://music.youtube.com/search?q=Djrum+Crawl"),
        bandcampURL: URL(string: "https://bandcamp.com/search?q=Djrum"),
        metadataStatus: .enrichedNoMatch
    )
}

/// What a successful `/proxy/metadata/album` fetch contributes: the enrichment
/// fields plus the three the V2 flowsheet row never carries
/// (`discogsArtistId`, `fullReleaseDate`, `bioTokens` — the #685 casualty list).
private let proxyResolvedMetadata = PlaycutMetadata(
    artist: ArtistMetadata(
        bio: "British electronic producer Felix Manuel.",
        bioTokens: [],
        discogsArtistId: 1_234
    ),
    album: AlbumMetadata(
        label: "Houndstooth",
        releaseYear: 2024,
        discogsURL: URL(string: "https://www.discogs.com/release/30000001"),
        discogsArtistId: 1_234,
        fullReleaseDate: "2024-10-25",
        artworkURL: URL(string: "https://i.discogs.com/meanings-edge.jpg")
    ),
    streaming: StreamingLinks(
        spotifyURL: URL(string: "https://open.spotify.com/track/crawl"),
        appleMusicURL: URL(string: "https://music.apple.com/album/crawl")
    )
)

// MARK: - PlaycutMetadataResolution (arrival-order independence)

@Suite("PlaycutMetadataResolution")
struct PlaycutMetadataResolutionTests {

    @Test("Starts empty and loading")
    func startsEmptyAndLoading() {
        let resolution = PlaycutMetadataResolution()

        #expect(resolution.metadata == .empty)
        #expect(resolution.isLoading)
    }

    @Test("A single initial resolve is rendered verbatim")
    func initialOnly() {
        var resolution = PlaycutMetadataResolution()
        resolution.recordInitial(proxyResolvedMetadata)

        #expect(resolution.metadata == proxyResolvedMetadata)
        #expect(!resolution.isLoading)
    }

    @Test("A repair that lands before the initial resolve is rendered verbatim")
    func repairOnly() throws {
        var resolution = PlaycutMetadataResolution()
        let repair = try #require(PlaycutMetadataResolver.inlineMetadata(for: enrichedRow()))
        resolution.recordRepair(repair)

        #expect(resolution.metadata == repair)
        #expect(!resolution.isLoading)
    }

    @Test("A slow initial resolve landing after the repair cannot overwrite it")
    func lateInitialResolveCannotClobberRepair() throws {
        // The #812 aggravator case: the proxy fetch takes ~180s (the QUIC read
        // timeouts this ticket documents) and returns *after* the repair. It
        // must not restore the pre-enrichment snapshot over the enriched one.
        var resolution = PlaycutMetadataResolution()

        let repair = try #require(PlaycutMetadataResolver.inlineMetadata(for: enrichedRow()))
        resolution.recordRepair(repair)

        // The stale answer: what the proxy had to say while the row was still
        // mid-enrichment — the label, and nothing else.
        resolution.recordInitial(PlaycutMetadata(album: AlbumMetadata(label: "Houndstooth")))

        #expect(resolution.metadata.releaseYear == 2024, "The repair's year must survive the late initial resolve")
        #expect(resolution.metadata.album.artworkURL != nil)
        #expect(resolution.metadata.album.genres == ["Electronic"])
        #expect(resolution.metadata.spotifyURL != nil)
    }

    @Test("A repair never removes information the initial resolve already had")
    func repairCoalescesRatherThanReplaces() throws {
        // A row landing as `enrichedNoMatch` carries only synthesized search
        // links. Replacing wholesale would strip the year, artwork, bio tokens
        // and Spotify/Apple links the proxy already resolved.
        var resolution = PlaycutMetadataResolution()
        resolution.recordInitial(proxyResolvedMetadata)

        let repair = try #require(PlaycutMetadataResolver.inlineMetadata(for: noMatchRow()))
        resolution.recordRepair(repair)

        // Kept from the initial resolve.
        #expect(resolution.metadata.releaseYear == 2024)
        #expect(resolution.metadata.album.artworkURL != nil)
        #expect(resolution.metadata.album.discogsArtistId == 1_234)
        #expect(resolution.metadata.album.fullReleaseDate == "2024-10-25")
        #expect(resolution.metadata.artist.bioTokens != nil)
        #expect(resolution.metadata.spotifyURL != nil)
        #expect(resolution.metadata.appleMusicURL != nil)

        // Gained from the repair.
        #expect(resolution.metadata.youtubeMusicURL != nil)
        #expect(resolution.metadata.bandcampURL != nil)
    }

    @Test("The repair wins on a field both sources populate")
    func repairWinsOnConflict() {
        var resolution = PlaycutMetadataResolution()
        resolution.recordInitial(PlaycutMetadata(album: AlbumMetadata(releaseYear: 2023)))
        resolution.recordRepair(PlaycutMetadata(album: AlbumMetadata(releaseYear: 2024)))

        #expect(
            resolution.metadata.releaseYear == 2024,
            "Backend's finished enrichment outranks whatever the proxy fuzzy-matched"
        )
    }
}

// MARK: - Coalescing

@Suite("PlaycutMetadata coalescing")
struct PlaycutMetadataCoalescingTests {

    @Test("Non-nil fields win, nil fields fall through")
    func albumCoalescing() {
        let preferred = AlbumMetadata(releaseYear: 2024, genres: ["Electronic"])
        let fallback = AlbumMetadata(
            label: "Houndstooth",
            releaseYear: 1999,
            artworkURL: URL(string: "https://i.discogs.com/a.jpg")
        )

        let merged = preferred.coalescing(over: fallback)

        #expect(merged.releaseYear == 2024, "preferred wins where populated")
        #expect(merged.label == "Houndstooth", "fallback fills where preferred is nil")
        #expect(merged.artworkURL != nil)
        #expect(merged.genres == ["Electronic"])
    }

    @Test("Coalescing over .empty is the identity")
    func coalescingOverEmptyIsIdentity() {
        #expect(proxyResolvedMetadata.coalescing(over: .empty) == proxyResolvedMetadata)
    }

    @Test("Coalescing .empty over a record preserves the record")
    func emptyCoalescingPreservesFallback() {
        #expect(PlaycutMetadata.empty.coalescing(over: proxyResolvedMetadata) == proxyResolvedMetadata)
    }
}

// MARK: - Resolver policy (pure)

@Suite("PlaycutMetadataResolver policy")
struct PlaycutMetadataResolverPolicyTests {

    @Test("inlineMetadata returns nil for a row with no V2 metadata at all")
    func inlineMetadataNilForBareRow() {
        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        )

        #expect(playcut.hasV2Metadata == false)
        #expect(PlaycutMetadataResolver.inlineMetadata(for: playcut) == nil)
    }

    @Test("inlineMetadata threads every enriched field off the V2 row")
    func inlineMetadataThreadsEnrichedFields() throws {
        let inline = try #require(PlaycutMetadataResolver.inlineMetadata(for: enrichedRow()))

        #expect(inline.album.label == "Houndstooth")
        #expect(inline.album.releaseYear == 2024)
        #expect(inline.album.discogsURL?.absoluteString == "https://www.discogs.com/release/30000001")
        #expect(inline.album.genres == ["Electronic"])
        #expect(inline.album.styles == ["Breakbeat", "Ambient"])
        #expect(inline.album.artworkURL?.absoluteString == "https://i.discogs.com/meanings-edge.jpg")
        #expect(inline.artistBio == "British electronic producer Felix Manuel.")
        #expect(inline.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/track/crawl")
    }

    @Test(
        "Only a row Backend is still working on is worth watching",
        arguments: [
            (MetadataStatus.pending, true),
            (MetadataStatus.enriching, true),
            (MetadataStatus.enrichedMatch, false),
            (MetadataStatus.enrichedNoMatch, false),
            (MetadataStatus.failedNoRetry, false),
        ] as [(MetadataStatus, Bool)]
    )
    func shouldObserveEnrichmentByStatus(status: MetadataStatus, expected: Bool) {
        let playcut = Playcut.stub(metadataStatus: status)
        #expect(PlaycutMetadataResolver.shouldObserveEnrichment(for: playcut) == expected)
    }

    @Test("A row with no metadataStatus is never worth watching")
    func shouldNotObserveStatuslessRow() {
        // `nil` means the v1 API, a feed predating #280's `metadata_status`, or
        // the Liked tab's synthesized `LikedSongSnapshot.toPlaycut()` (which
        // hardcodes id 0). None of them will ever produce a status transition,
        // so subscribing only pins the playlist polling loop open for nothing.
        #expect(PlaycutMetadataResolver.shouldObserveEnrichment(for: Playcut.stub(metadataStatus: nil)) == false)
    }
}

// MARK: - Resolution and repair against a live service
//
// Declared as an extension of `PlaycutMetadataServiceHTTPTests` — see this
// file's header for why there is no second `QueuedStubURLProtocol` adopter.

extension PlaycutMetadataServiceHTTPTests {

    private static func makeResolver() -> PlaycutMetadataResolver {
        PlaycutMetadataResolver(
            service: PlaycutMetadataService(
                urlSession: QueuedStubURLProtocol.makeSession(),
                cache: CacheCoordinator(cache: PlaycutMetadataMockCache())
            )
        )
    }

    /// A `/proxy/metadata/album` body with every field null — enough to satisfy
    /// a fetch without contributing anything, so a test can tell "the proxy was
    /// consulted" apart from "the proxy had something to say".
    private static var emptyAlbumBody: Data {
        """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
    }

    // MARK: resolve(for:)

    @Test("A row that is already terminal on first appearance makes zero proxy requests (#685)")
    func terminalRowMakesNoProxyRequest() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let resolved = await resolver.resolve(for: enrichedRow())

        #expect(
            QueuedStubURLProtocol.capturedRequests().isEmpty,
            "Terminal rows must never spend a /proxy/metadata/album round-trip"
        )
        #expect(resolved.releaseYear == 2024)
    }

    @Test("A row still enriching falls through to the proxy")
    func enrichingRowFallsThroughToProxy() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let resolved = await resolver.resolve(for: enrichingRow())

        #expect(!QueuedStubURLProtocol.capturedRequests().isEmpty)
        // The pre-enrichment card: the label renders, everything else is blank.
        #expect(resolved.label == "Houndstooth")
        #expect(resolved.releaseYear == nil)
        #expect(resolved.hasStreamingLinks == false)
    }

    // MARK: repairs(for:playlists:)

    @Test("An enriching → enriched_match transition repairs the card", .timeLimit(.minutes(1)))
    func transitionRepairsTheCard() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichingRow()]))
        continuation.yield(.stub(playcuts: [enrichedRow()]))

        let repaired = try #require(await repairs.next())

        #expect(repaired.releaseYear == 2024)
        #expect(repaired.album.genres == ["Electronic"])
        #expect(repaired.album.artworkURL != nil)
        #expect(repaired.artistBio == "British electronic producer Felix Manuel.")
        #expect(repaired.spotifyURL?.absoluteString == "https://open.spotify.com/track/crawl")

        continuation.finish()
    }

    @Test("The repair spends zero /proxy/metadata/album requests (#685 regression guard)", .timeLimit(.minutes(1)))
    func repairMakesNoProxyRequest() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow()]))
        _ = await repairs.next()

        #expect(
            QueuedStubURLProtocol.capturedRequests().isEmpty,
            "The row arrived terminal, so the repair renders from inline fields alone"
        )

        continuation.finish()
    }

    @Test(
        "A row that reached terminal before the card subscribed is still repaired",
        .timeLimit(.minutes(1))
    )
    func repairsAgainstTheCurrentRowAtSubscribeTime() async throws {
        // The seed race `terminalMetadataTransitions` structurally cannot
        // report (#443's baseline snapshot is discarded by design): the cover
        // transition plus task scheduling costs a few hundred ms inside a ~2s
        // window, so the row can flip to terminal between row-tap and the
        // card's subscription. Reconciling against the store's *current* row —
        // not only against subsequent transitions — is what closes it.
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        // The very first snapshot the card sees already has the row terminal.
        continuation.yield(.stub(playcuts: [enrichedRow()]))

        let repaired = try #require(await repairs.next())
        #expect(repaired.releaseYear == 2024)

        continuation.finish()
    }

    @Test("Other rows landing their enrichment never repaint this card", .timeLimit(.minutes(1)))
    func otherRowsAreIgnored() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(id: 5305276), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow(id: 5305277)]))
        continuation.yield(.stub(playcuts: [enrichedRow(id: 5305277), enrichedRow(id: 5305276)]))

        let repaired = try #require(await repairs.next())
        #expect(repaired.releaseYear == 2024)

        continuation.finish()
    }

    @Test("The card is repaired at most once, then the stream finishes", .timeLimit(.minutes(1)))
    func repairsAtMostOnce() async throws {
        // The #685 budget depends on this: a repair fires on the transition
        // into terminal and never again, however many further snapshots carry
        // the (still terminal) row.
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow()]))
        continuation.yield(.stub(playcuts: [enrichedRow()]))
        continuation.yield(.stub(playcuts: [enrichedRow()]))

        _ = try #require(await repairs.next())

        #expect(await repairs.next() == nil, "One repair per card, then done")
        #expect(QueuedStubURLProtocol.capturedRequests().isEmpty)

        continuation.finish()
    }

    @Test(
        "A row already terminal at first appearance yields no repair at all",
        .timeLimit(.minutes(1))
    )
    func alreadyTerminalRowYieldsNoRepair() async throws {
        // `shouldObserveEnrichment` is the caller-facing guard; `repairs`
        // enforces it too so a caller that skips the check can't spend a
        // subscription — or a resolve — on a row Backend already finished.
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichedRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow()]))

        #expect(await repairs.next() == nil)
        #expect(QueuedStubURLProtocol.capturedRequests().isEmpty)

        continuation.finish()
    }

    @Test("A row with no metadataStatus yields no repair at all", .timeLimit(.minutes(1)))
    func statuslessRowYieldsNoRepair() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let resolver = Self.makeResolver()

        let v1Row = Playcut.stub(id: 0, metadataStatus: nil)
        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: v1Row, playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [v1Row]))

        #expect(await repairs.next() == nil)

        continuation.finish()
    }

    // MARK: - Repair write-back (#821)

    @Test("A repair writes the terminal row's inline album back into the cache", .timeLimit(.minutes(1)))
    func repairWritesAlbumBackIntoCache() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)
        let resolver = PlaycutMetadataResolver(service: service)

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow()]))
        _ = try #require(await repairs.next())
        continuation.finish()

        let albumKey = MetadataCacheKey.album(artistName: "Djrum", releaseTitle: "Meaning's Edge")
        let cachedAlbum: AlbumMetadata? = try? await cache.value(for: albumKey)
        let album = try #require(cachedAlbum, "The repair must write the album it resolved back into the cache")
        #expect(album.releaseYear == 2024)
        #expect(album.genres == ["Electronic"])
    }

    @Test(
        "The repair write-back never overwrites a cached discogsArtistId or fullReleaseDate the proxy already resolved",
        .timeLimit(.minutes(1))
    )
    func repairWriteBackPreservesProxyOnlyFields() async throws {
        // The naive-write-back hazard #821 documents: the inline album this
        // repair branch produces carries no discogsArtistId/fullReleaseDate
        // (the #685 casualty list — only /proxy/metadata/album supplies
        // those). If the write-back replaced rather than merged, an
        // already-cached proxy answer would be downgraded to nil, and any
        // later card that reads this cache entry would get no artist bio at
        // all (fetchArtistMetadata(discogsArtistId:) returns .empty on nil).
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)
        let resolver = PlaycutMetadataResolver(service: service)

        let albumKey = MetadataCacheKey.album(artistName: "Djrum", releaseTitle: "Meaning's Edge")
        let proxyResolvedAlbum = AlbumMetadata(
            label: "Houndstooth",
            releaseYear: 2024,
            discogsURL: URL(string: "https://www.discogs.com/release/30000001"),
            discogsArtistId: 1_234,
            fullReleaseDate: "2024-10-25",
            artworkURL: URL(string: "https://i.discogs.com/meanings-edge.jpg")
        )
        await cache.set(value: proxyResolvedAlbum, for: albumKey, lifespan: .sevenDays)

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow()]))
        _ = try #require(await repairs.next())
        continuation.finish()

        let cachedAlbum: AlbumMetadata? = try? await cache.value(for: albumKey)
        let album = try #require(cachedAlbum)
        #expect(album.discogsArtistId == 1_234, "The repair write-back must not erase a discogsArtistId the cache already had")
        #expect(album.fullReleaseDate == "2024-10-25", "The repair write-back must not erase a fullReleaseDate the cache already had")
    }

    @Test("A repair write-back that still lacks discogsArtistId gets the short TTL, not seven days", .timeLimit(.minutes(1)))
    func repairWriteBackWithoutArtistIdUsesShortTTL() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)
        let resolver = PlaycutMetadataResolver(service: service)

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow()]))
        _ = try #require(await repairs.next())
        continuation.finish()

        let albumKey = MetadataCacheKey.album(artistName: "Djrum", releaseTitle: "Meaning's Edge")
        let metadata = mockCache.metadata(for: albumKey)
        #expect(metadata != nil)
        #expect(
            metadata?.lifespan == PlaycutMetadataService.sparseAlbumLifespan,
            "A repaired album still missing discogsArtistId must not get the full seven-day TTL"
        )
    }

    @Test(
        "A repair write-back that already carries discogsArtistId (from a pre-existing cache entry) keeps the seven-day TTL",
        .timeLimit(.minutes(1))
    )
    func repairWriteBackWithArtistIdKeepsSevenDayTTL() async throws {
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)
        let resolver = PlaycutMetadataResolver(service: service)

        let albumKey = MetadataCacheKey.album(artistName: "Djrum", releaseTitle: "Meaning's Edge")
        await cache.set(
            value: AlbumMetadata(discogsArtistId: 1_234),
            for: albumKey,
            lifespan: PlaycutMetadataService.sparseAlbumLifespan
        )

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [enrichedRow()]))
        _ = try #require(await repairs.next())
        continuation.finish()

        let metadata = mockCache.metadata(for: albumKey)
        #expect(metadata?.lifespan == .sevenDays)
    }

    @Test(
        "A repair carrying no enrichment does not manufacture a cold album cache entry",
        .timeLimit(.minutes(1))
    )
    func repairWithNothingToContributeLeavesAColdCacheCold() async throws {
        // Terminal is not the same as enriched. `hasV2Metadata` is `true` for
        // every terminal row by its first clause alone, so `resolve(for:)`
        // still builds an inline album for an `enrichedNoMatch` free-text
        // play — and that album is the label and nothing else, i.e. `isSparse`.
        //
        // Merged over a warm entry that's harmless, because coalescing can
        // only add. Merged over a cold one it would *install* the
        // pre-enrichment shape #812 exists to bound: for the next
        // `sparseAlbumLifespan` a sibling row resolving through the proxy
        // branch would read it as an album cache hit, render from it, lose its
        // artist bio to the absent discogsArtistId, and never persist the real
        // answer the proxy had just returned.
        QueuedStubURLProtocol.setBody(Self.emptyAlbumBody)
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)
        let resolver = PlaycutMetadataResolver(service: service)

        let (playlists, continuation) = AsyncStream.makeStream(of: Playlist.self)
        var repairs = resolver.repairs(for: enrichingRow(), playlists: playlists).makeAsyncIterator()

        continuation.yield(.stub(playcuts: [noMatchRow()]))
        let repaired = try #require(await repairs.next())
        continuation.finish()

        // The card still repairs — this is about the cache, not the render.
        #expect(repaired.album.isSparse, "Precondition: the no-match row's inline album carries no enrichment")

        let albumKey = MetadataCacheKey.album(artistName: "Djrum", releaseTitle: "Meaning's Edge")
        #expect(
            mockCache.metadata(for: albumKey) == nil,
            "A repair with nothing to contribute must leave a cold album key for the proxy branch to fill"
        )
    }
}
