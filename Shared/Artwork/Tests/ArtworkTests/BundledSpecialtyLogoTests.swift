//
//  BundledSpecialtyLogoTests.swift
//  Artwork
//
//  Tests for the DEBUG-only bundled specialty logos: slug lookup and the rule
//  that a server logo URL always wins over the bundled image.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
import SwiftUI
import Core
import Playlist
import PlaylistTesting
@testable import Artwork
@testable import Caching

private func program(slug: String, squareURL: URL? = nil) -> SpecialtyShowRef {
    .stub(id: 7, slug: slug, name: "Show", shortName: "SH", squareURL: squareURL)
}

@Suite("BundledSpecialtyLogo")
struct BundledSpecialtyLogoTests {

#if DEBUG
    @Test("The NSE slug resolves to a square bundled image")
    func nseResolves() throws {
        let image = try #require(SpecialtyArtwork.bundledLogo(for: program(slug: "new-science-experience")))
        #expect(image.width == image.height)
        #expect(image.width > 0)
    }

    @Test("The bundled image is downsampled to maxPixelSize", arguments: [64, 240])
    func downsamples(maxPixelSize: Int) throws {
        let image = try #require(SpecialtyArtwork.bundledLogo(for: program(slug: "new-science-experience"), maxPixelSize: maxPixelSize))
        #expect(max(image.width, image.height) == maxPixelSize)
    }

    @Test("An unknown slug has no bundled image", arguments: ["hogwash", "", "New-Science-Experience"])
    func unknownSlugDoesNotResolve(slug: String) {
        #expect(SpecialtyArtwork.bundledLogo(for: program(slug: slug)) == nil)
    }

    @Test("A server logo URL takes precedence over the bundled image")
    func serverLogoWins() {
        let url = URL(string: "https://example.com/nse.png")!
        let nse = program(slug: "new-science-experience", squareURL: url)
        #expect(SpecialtyArtwork.logoURL(for: nse) == url)
        #expect(SpecialtyArtwork.bundledLogo(for: nse) == nil)
    }
#else
    @Test("Release builds never resolve a bundled image")
    func releaseHasNone() {
        #expect(SpecialtyArtwork.bundledLogo(for: program(slug: "new-science-experience")) == nil)
    }
#endif
}

#if DEBUG
@Suite("SpecialtyArtwork.logo bundled fallback")
struct BundledLogoFallbackTests {

    private let nse = SpecialtyShowRef.stub(id: 9, slug: "new-science-experience", name: "New Science Experience")

    @Test("A program with no logo URL falls back to its bundled logo, through both entry points, without a download")
    func fallsBack() async {
        let session = MockWebSession()
        let cache = CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))

        #expect(await SpecialtyArtwork.logo(for: nse, cache: cache, session: session) != nil)
        #expect(await SpecialtyArtwork.logo(for: nse, maxPixelSize: 120, cache: cache, session: session) != nil)
        #expect(session.requestedURLs.isEmpty)
    }
}
#endif

@Suite("SpecialtyArtwork resolution")
struct SpecialtyResolutionTests {

    private let nse = SpecialtyShowRef.stub(id: 9, slug: "new-science-experience", name: "New Science Experience")
    private let logoURL = URL(string: "https://example.com/hogwash.png")!

    /// The bundled logo exists only in DEBUG builds.
    #if DEBUG
    private let hasBundledLogo = true
    #else
    private let hasBundledLogo = false
    #endif

    enum Source { case serverLoads, serverFails, noURLBundled, noURLNoBundled }

    @Test(
        "Resolves the server logo, else the bundled logo (DEBUG only), else nothing",
        arguments: [
            (source: Source.serverLoads, downloads: 1),
            (source: .serverFails, downloads: 1),
            (source: .noURLBundled, downloads: 0),
            (source: .noURLNoBundled, downloads: 0),
        ]
    )
    func resolves(source: Source, downloads: Int) async {
        let session = MockWebSession()
        let ref: SpecialtyShowRef
        let expectsImage: Bool
        switch source {
        case .serverLoads:
            session.dataToReturn = CGImage.testImage.pngDataCompatibility!
            ref = .stub(squareURL: logoURL)
            expectsImage = true
        case .serverFails:
            session.errorToThrow = ServiceError.noResults
            ref = .stub(squareURL: logoURL)
            expectsImage = false
        case .noURLBundled:
            ref = nse
            expectsImage = hasBundledLogo
        case .noURLNoBundled:
            ref = .stub()
            expectsImage = false
        }
        let cache = CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))

        let image = await SpecialtyArtwork.logo(for: ref, cache: cache, session: session)

        #expect((image != nil) == expectsImage)
        #expect(session.requestedURLs.count == downloads)
    }
}

#if DEBUG
@Suite("SpecialtyArtworkView bundled logo")
@MainActor
struct SpecialtyArtworkViewBundledTests {

    @Test("The view's body never draws the bundled logo itself; until its task resolves one, it draws the tile")
    func bodyDrawsTheTileUntilResolved() async throws {
        let nse = SpecialtyShowRef.stub(id: 9, slug: "new-science-experience", name: "New Science Experience")
        // The resolver never finishes, so only what body draws is on screen.
        let view = SpecialtyArtworkView(program: nse, size: 60) { _ in
            try? await Task.sleep(for: .seconds(60))
            return nil
        }
        let tile = SpecialtyTileView(program: nse).frame(width: 60, height: 60)

        let drawn = try #require(ImageRenderer(content: view).cgImage?.pngDataCompatibility)
        let expected = try #require(ImageRenderer(content: tile).cgImage?.pngDataCompatibility)

        #expect(drawn == expected)
    }
}
#endif
