//
//  OEmbedClientTests.swift
//  MusicShareKit
//
//  Tests for the shared oEmbed fetch-and-parse used by SoundCloudService and
//  YouTubeMusicService.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import MusicShareKit

@Suite("OEmbedClient Tests", .serialized)
struct OEmbedClientTests {

    @Test("Parses title, author_name, and thumbnail_url from a valid response")
    func parsesValidResponse() async throws {
        let interceptor = OEmbedRequestInterceptor()
        interceptor.responseBody = """
        {
            "title": "la paradoja",
            "author_name": "Juana Molina",
            "thumbnail_url": "https://example.com/artwork.jpg"
        }
        """.data(using: .utf8)!
        let session = makeOEmbedSession(interceptor: interceptor)

        let response = try await OEmbedClient.fetch(
            endpoint: "https://soundcloud.com/oembed",
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: session
        )

        #expect(response.title == "la paradoja")
        #expect(response.authorName == "Juana Molina")
        #expect(response.thumbnailURL == URL(string: "https://example.com/artwork.jpg"))
    }

    @Test("Request targets the given endpoint with url and format=json query items")
    func requestQueryItems() async throws {
        let interceptor = OEmbedRequestInterceptor()
        interceptor.responseBody = "{}".data(using: .utf8)!
        let session = makeOEmbedSession(interceptor: interceptor)
        let trackURL = URL(string: "https://www.youtube.com/watch?v=7SKorvPNRDI")!

        _ = try await OEmbedClient.fetch(
            endpoint: "https://www.youtube.com/oembed",
            trackURL: trackURL,
            session: session
        )

        let capturedURL = try #require(interceptor.lastRequest?.url)
        let components = try #require(URLComponents(url: capturedURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "www.youtube.com")
        #expect(components.path == "/oembed")
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "url", value: trackURL.absoluteString)))
        #expect(queryItems.contains(URLQueryItem(name: "format", value: "json")))
    }

    @Test("Missing fields in the response surface as nil rather than throwing")
    func missingFieldsAreNil() async throws {
        let interceptor = OEmbedRequestInterceptor()
        interceptor.responseBody = "{}".data(using: .utf8)!
        let session = makeOEmbedSession(interceptor: interceptor)

        let response = try await OEmbedClient.fetch(
            endpoint: "https://soundcloud.com/oembed",
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: session
        )

        #expect(response.title == nil)
        #expect(response.authorName == nil)
        #expect(response.thumbnailURL == nil)
    }

    @Test("A response body that isn't a JSON object returns an empty response instead of throwing")
    func nonObjectBodyReturnsEmpty() async throws {
        let interceptor = OEmbedRequestInterceptor()
        interceptor.responseBody = "[1, 2, 3]".data(using: .utf8)!
        let session = makeOEmbedSession(interceptor: interceptor)

        let response = try await OEmbedClient.fetch(
            endpoint: "https://soundcloud.com/oembed",
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: session
        )

        #expect(response.title == nil)
        #expect(response.authorName == nil)
        #expect(response.thumbnailURL == nil)
    }

    /// `endpoint` is a parameter, so an unparseable value must not be able to trap. The
    /// pre-refactor code force-unwrapped a string literal, which was safe by construction;
    /// once the endpoint became caller-supplied the force-unwrap became a crash path.
    @Test(
        "An endpoint string URLComponents can't parse returns an empty response instead of trapping",
        arguments: ["https://exa mple.com/oembed", "http://[::1", "https://ex^ample.com"]
    )
    func unparseableEndpointReturnsEmpty(endpoint: String) async throws {
        let interceptor = OEmbedRequestInterceptor()
        interceptor.responseBody = #"{"title": "should never be reached"}"#.data(using: .utf8)!
        let session = makeOEmbedSession(interceptor: interceptor)

        let response = try await OEmbedClient.fetch(
            endpoint: endpoint,
            trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
            session: session
        )

        #expect(response.title == nil)
        #expect(response.authorName == nil)
        #expect(response.thumbnailURL == nil)
        #expect(interceptor.lastRequest == nil, "No request should be issued for an unparseable endpoint")
    }

    @Test("Malformed JSON throws rather than returning an empty response")
    func malformedJSONThrows() async throws {
        let interceptor = OEmbedRequestInterceptor()
        interceptor.responseBody = "not json".data(using: .utf8)!
        let session = makeOEmbedSession(interceptor: interceptor)

        await #expect(throws: (any Error).self) {
            _ = try await OEmbedClient.fetch(
                endpoint: "https://soundcloud.com/oembed",
                trackURL: URL(string: "https://soundcloud.com/juanamolina/la-paradoja")!,
                session: session
            )
        }
    }
}

// MARK: - Test Helpers

/// URLProtocol subclass that intercepts requests and returns a configured response body,
/// mirroring the AuthRequestInterceptor pattern in DefaultAuthNetworkClientTests.swift.
private final class OEmbedRequestInterceptor: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var current: OEmbedRequestInterceptor?

    nonisolated(unsafe) var responseBody: Data = Data()
    nonisolated(unsafe) var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.current?.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.current?.responseBody ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeOEmbedSession(interceptor: OEmbedRequestInterceptor) -> URLSession {
    OEmbedRequestInterceptor.current = interceptor
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OEmbedRequestInterceptor.self]
    return URLSession(configuration: config)
}
