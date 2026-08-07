//
//  PlaycutMetadataResolverTests.swift
//  Metadata
//
//  Tests for PlaycutMetadataResolver: the detail card's inline-vs-proxy
//  resolution decision, and the terminal-transition re-resolution that repairs
//  a card opened during the ~2s pre-enrichment window (#812).
//
//  Created by Jake Bromberg on 08/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//
//  This suite owns `MetadataResolverMockWebSession`, its own stub-`URLProtocol`
//  double, for the same reason `PlaycutMetadataServiceV2FallbackTests.swift`
//  owns `MetadataV2MockWebSession`: `URLProtocol` registration is by class, so
//  two suites sharing one double would race even when each is individually
//  `.serialized`. Hence the file-scoped type and the `.serialized` trait here.
//

import Testing
import Foundation
import os
import Core
import Playlist
import PlaylistTesting
@testable import Caching
@testable import Metadata

// MARK: - Mock WebSession for this file's suite

/// See `PlaycutMetadataServiceCachingTests.swift`'s `MetadataMockWebSession`
/// for the design rationale — this is the same shape, kept as a separate type
/// so this suite's `.serialized` trait doesn't have to share static state with
/// the other suites'.
final class MetadataResolverMockWebSession: @unchecked Sendable {
    private struct State {
        var responses: [String: Data] = [:]
        var requestedURLs: [URL] = []
        var requestCount = 0
    }

    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            let matchedData: Data? = MetadataResolverMockWebSession.lock.withLock { state in
                state.requestCount += 1
                state.requestedURLs.append(url)
                let urlString = url.absoluteString
                return state.responses.first { urlString.contains($0.key) }?.value
            }

            guard let matchedData, let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
                return
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: matchedData)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static let lock = OSAllocatedUnfairLock(initialState: State())

    /// The `URLSession` to inject as `PlaycutMetadataService`'s `urlSession`.
    let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }()

    var responses: [String: Data] {
        get { Self.lock.withLock { $0.responses } }
        set { Self.lock.withLock { $0.responses = newValue } }
    }

    var requestedURLs: [URL] { Self.lock.withLock { $0.requestedURLs } }
    var requestCount: Int { Self.lock.withLock { $0.requestCount } }

    init() {
        reset()
    }

    func reset() {
        Self.lock.withLock { $0 = State() }
    }
}

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

private func makeResolver(
    session: MetadataResolverMockWebSession,
    cache: CacheCoordinator
) -> PlaycutMetadataResolver {
    PlaycutMetadataResolver(
        service: PlaycutMetadataService(urlSession: session.urlSession, cache: cache)
    )
}

// MARK: - Tests

@Suite("PlaycutMetadataResolver", .serialized)
struct PlaycutMetadataResolverTests {

    // MARK: - Inline construction

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

    // MARK: - resolve(for:)

    @Test("A row that is already terminal on first appearance makes zero proxy requests (#685)")
    func terminalRowMakesNoProxyRequest() async throws {
        let session = MetadataResolverMockWebSession()
        let cache = CacheCoordinator(cache: PlaycutMetadataMockCache())
        let resolver = makeResolver(session: session, cache: cache)

        let resolved = await resolver.resolve(for: enrichedRow())

        #expect(session.requestCount == 0, "Terminal rows must never spend a /proxy/metadata/album round-trip")
        #expect(resolved.releaseYear == 2024)
    }

    @Test("A row still enriching falls through to the proxy")
    func enrichingRowFallsThroughToProxy() async throws {
        let session = MetadataResolverMockWebSession()
        session.responses["proxy/metadata/album"] = """
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
        let cache = CacheCoordinator(cache: PlaycutMetadataMockCache())
        let resolver = makeResolver(session: session, cache: cache)

        let resolved = await resolver.resolve(for: enrichingRow())

        #expect(session.requestCount >= 1)
        // The pre-enrichment card: the label renders, everything else is blank.
        #expect(resolved.label == "Houndstooth")
        #expect(resolved.releaseYear == nil)
        #expect(resolved.hasStreamingLinks == false)
    }

    // MARK: - Terminal-transition re-resolution (#812)

    @Test("An enriching → enriched_match transition re-resolves the card with the full record")
    func terminalTransitionReresolves() async throws {
        let session = MetadataResolverMockWebSession()
        let cache = CacheCoordinator(cache: PlaycutMetadataMockCache())
        let resolver = makeResolver(session: session, cache: cache)

        let (transitions, continuation) = AsyncStream.makeStream(of: Playcut.self)
        var reresolutions = resolver.reresolutions(
            for: enrichingRow(),
            transitions: transitions
        ).makeAsyncIterator()

        continuation.yield(enrichedRow())

        let repaired = try #require(await reresolutions.next())

        #expect(repaired.releaseYear == 2024)
        #expect(repaired.album.genres == ["Electronic"])
        #expect(repaired.album.artworkURL != nil)
        #expect(repaired.artistBio == "British electronic producer Felix Manuel.")
        #expect(repaired.spotifyURL?.absoluteString == "https://open.spotify.com/track/crawl")

        continuation.finish()
    }

    @Test("The re-resolve spends zero /proxy/metadata/album requests (#685 regression guard)")
    func terminalTransitionMakesNoProxyRequest() async throws {
        let session = MetadataResolverMockWebSession()
        let cache = CacheCoordinator(cache: PlaycutMetadataMockCache())
        let resolver = makeResolver(session: session, cache: cache)

        let (transitions, continuation) = AsyncStream.makeStream(of: Playcut.self)
        var reresolutions = resolver.reresolutions(
            for: enrichingRow(),
            transitions: transitions
        ).makeAsyncIterator()

        continuation.yield(enrichedRow())
        _ = await reresolutions.next()

        #expect(
            session.requestCount == 0,
            "The row transitioned *into* terminal, so the re-resolve renders from inline fields alone"
        )

        continuation.finish()
    }

    @Test("Transitions belonging to other rows are ignored")
    func otherRowsAreIgnored() async throws {
        let session = MetadataResolverMockWebSession()
        let cache = CacheCoordinator(cache: PlaycutMetadataMockCache())
        let resolver = makeResolver(session: session, cache: cache)

        let (transitions, continuation) = AsyncStream.makeStream(of: Playcut.self)
        var reresolutions = resolver.reresolutions(
            for: enrichingRow(id: 5305276),
            transitions: transitions
        ).makeAsyncIterator()

        // A different flowsheet row landing its enrichment must not repaint
        // this card; only the matching id gets through.
        continuation.yield(enrichedRow(id: 5305277))
        continuation.yield(enrichedRow(id: 5305276))

        let repaired = try #require(await reresolutions.next())
        #expect(repaired.releaseYear == 2024)

        // The 5305277 yield produced nothing of its own — after the matching
        // row is consumed and the stream finishes, there is no second element.
        continuation.finish()
        #expect(await reresolutions.next() == nil)
    }

    @Test("A row already terminal at first appearance never subscribes, so it can never re-resolve")
    func alreadyTerminalRowYieldsNothing() async throws {
        let session = MetadataResolverMockWebSession()
        let cache = CacheCoordinator(cache: PlaycutMetadataMockCache())
        let resolver = makeResolver(session: session, cache: cache)

        #expect(
            resolver.shouldObserveEnrichment(for: enrichedRow()) == false,
            "Backend already finished this row — there is nothing to repair, and #685 forbids re-spending on it"
        )
        #expect(resolver.shouldObserveEnrichment(for: enrichingRow()))
    }
}
