//
//  SpecialtyArtworkTests.swift
//  Artwork
//
//  Tests for the specialty program logo: the URL-and-fallback decision and the
//  URL-keyed artwork cache entry point it loads through.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
import Core
import Playlist
@testable import Artwork
@testable import Caching

private let logoURL = URL(string: "https://example.com/hogwash.png")!

private func program(squareURL: URL?, hasArtwork: Bool = true) -> SpecialtyShowRef {
    SpecialtyShowRef(
        id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW",
        artwork: hasArtwork ? .init(squareURL: squareURL) : nil
    )
}

@Suite("SpecialtyArtwork")
struct SpecialtyArtworkTests {

    @Test("Chooses the logo URL only when the program has one")
    func logoURLSelection() {
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: logoURL)) == logoURL)
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: nil)) == nil)
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: nil, hasArtwork: false)) == nil)
    }

    @Test(
        "Shows the tile unless a logo URL exists and has loaded",
        arguments: [
            (hasURL: false, state: SpecialtyArtwork.LogoState.loading, showsLogo: false),
            (hasURL: false, state: .loaded, showsLogo: false),
            (hasURL: true, state: .loading, showsLogo: false),
            (hasURL: true, state: .failed, showsLogo: false),
            (hasURL: true, state: .loaded, showsLogo: true),
        ]
    )
    func fallbackDecision(hasURL: Bool, state: SpecialtyArtwork.LogoState, showsLogo: Bool) {
        let url = hasURL ? logoURL : nil
        #expect(SpecialtyArtwork.showsLogo(url: url, state: state) == showsLogo)
    }
}

@Suite("CacheCoordinator.image(from:)")
struct URLKeyedArtworkCacheTests {

    private func makeCache() -> CacheCoordinator {
        CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
    }

    @Test("A second request for the same URL is served from the cache")
    func secondRequestDoesNotRefetch() async throws {
        let session = MockWebSession()
        session.dataToReturn = CGImage.testImage.pngDataCompatibility!
        let cache = makeCache()

        _ = try await cache.image(from: logoURL, session: session)
        _ = try await cache.image(from: logoURL, session: session)

        #expect(session.requestedURLs == [logoURL])
    }

    @Test("A failed download throws and is not cached")
    func failureIsNotCached() async throws {
        let session = MockWebSession()
        session.errorToThrow = ServiceError.noResults
        let cache = makeCache()

        await #expect(throws: (any Error).self) { try await cache.image(from: logoURL, session: session) }

        session.errorToThrow = nil
        session.dataToReturn = CGImage.testImage.pngDataCompatibility!
        _ = try await cache.image(from: logoURL, session: session)
        #expect(session.requestedURLs.count == 2)
    }

    @Test("Undecodable data throws")
    func undecodableDataThrows() async {
        let session = MockWebSession()
        session.dataToReturn = Data("not an image".utf8)

        await #expect(throws: (any Error).self) { try await makeCache().image(from: logoURL, session: session) }
    }
}
