//
//  OEmbedClientTests.swift
//  MusicShareKit
//
//  Tests for the shared oEmbed fetch-and-parse used by SoundCloudService and
//  YouTubeMusicService.
//
//  Declared as its own `@Suite` rather than an extension: the stubbing below
//  rides `CoreTesting`'s `QueuedStubURLProtocol` (through its
//  `PatternRoutingWebSession` facade), whose state is static — at most one
//  adopting suite per test bundle. `DefaultAuthNetworkClientTests`, this
//  file's prior host, moved to `ListenerAuthTests` in WXYC/wxyc-ios-64#1099,
//  so this is now the only adopter of `QueuedStubURLProtocol` left in this
//  bundle.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreTesting
import Foundation
import Testing
@testable import MusicShareKit

@Suite("OEmbedClient Tests", .serialized)
struct OEmbedClientTests {

    @Test("oEmbed: parses title, author_name, and thumbnail_url from a valid response")
    func oEmbedParsesValidResponse() async throws {
        let web = PatternRoutingWebSession()
        web.responses["soundcloud.com/oembed"] = Data("""
        {
            "title": "la paradoja",
            "author_name": "Juana Molina",
            "thumbnail_url": "https://example.com/artwork.jpg"
        }
        """.utf8)

        let response = try await OEmbedClient.fetch(
            endpoint: "https://soundcloud.com/oembed",
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: web.urlSession
        )

        #expect(response.title == "la paradoja")
        #expect(response.authorName == "Juana Molina")
        #expect(response.thumbnailURL == URL(string: "https://example.com/artwork.jpg"))
    }

    @Test("oEmbed: request targets the given endpoint with url and format=json query items")
    func oEmbedRequestQueryItems() async throws {
        let web = PatternRoutingWebSession()
        web.responses["www.youtube.com/oembed"] = Data("{}".utf8)
        let trackURL = URL(string: "https://www.youtube.com/watch?v=7SKorvPNRDI")!

        _ = try await OEmbedClient.fetch(
            endpoint: "https://www.youtube.com/oembed",
            trackURL: trackURL,
            session: web.urlSession
        )

        let capturedURL = try #require(web.requestedURLs.last)
        let components = try #require(URLComponents(url: capturedURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "www.youtube.com")
        #expect(components.path == "/oembed")
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "url", value: trackURL.absoluteString)))
        #expect(queryItems.contains(URLQueryItem(name: "format", value: "json")))
    }

    @Test("oEmbed: missing fields in the response surface as nil rather than throwing")
    func oEmbedMissingFieldsAreNil() async throws {
        let web = PatternRoutingWebSession()
        web.responses["soundcloud.com/oembed"] = Data("{}".utf8)

        let response = try await OEmbedClient.fetch(
            endpoint: "https://soundcloud.com/oembed",
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: web.urlSession
        )

        #expect(response.title == nil)
        #expect(response.authorName == nil)
        #expect(response.thumbnailURL == nil)
    }

    @Test("oEmbed: a response body that isn't a JSON object returns an empty response instead of throwing")
    func oEmbedNonObjectBodyReturnsEmpty() async throws {
        let web = PatternRoutingWebSession()
        web.responses["soundcloud.com/oembed"] = Data("[1, 2, 3]".utf8)

        let response = try await OEmbedClient.fetch(
            endpoint: "https://soundcloud.com/oembed",
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: web.urlSession
        )

        #expect(response.title == nil)
        #expect(response.authorName == nil)
        #expect(response.thumbnailURL == nil)
    }

    /// `endpoint` is a parameter, so an unparseable value must not be able to trap. The
    /// pre-refactor code force-unwrapped a string literal, which was safe by construction;
    /// once the endpoint became caller-supplied the force-unwrap became a crash path.
    @Test(
        "oEmbed: an endpoint string URLComponents can't parse returns an empty response instead of trapping",
        arguments: ["https://exa mple.com/oembed", "http://[::1", "https://ex^ample.com"]
    )
    func oEmbedUnparseableEndpointReturnsEmpty(endpoint: String) async throws {
        let web = PatternRoutingWebSession()
        web.responses["oembed"] = Data(#"{"title": "should never be reached"}"#.utf8)

        let response = try await OEmbedClient.fetch(
            endpoint: endpoint,
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: web.urlSession
        )

        #expect(response.title == nil)
        #expect(response.authorName == nil)
        #expect(response.thumbnailURL == nil)
        #expect(web.requestCount == 0, "No request should be issued for an unparseable endpoint")
    }

    @Test("oEmbed: malformed JSON throws rather than returning an empty response")
    func oEmbedMalformedJSONThrows() async throws {
        let web = PatternRoutingWebSession()
        web.responses["soundcloud.com/oembed"] = Data("not json".utf8)

        await #expect(throws: (any Error).self) {
            _ = try await OEmbedClient.fetch(
                endpoint: "https://soundcloud.com/oembed",
                trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
                session: web.urlSession
            )
        }
    }
}
