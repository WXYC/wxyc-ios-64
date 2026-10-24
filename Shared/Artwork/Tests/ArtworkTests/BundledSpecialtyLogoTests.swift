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
        let accent = (red: 179, green: 38, blue: 30)
        let nse = SpecialtyShowRef.stub(id: 9, slug: "new-science-experience", name: "New Science Experience", accentColor: "#B3261E")
        // The resolver never finishes, so only what body draws is on screen.
        let view = SpecialtyArtworkView(program: nse, size: 60) { _ in
            try? await Task.sleep(for: .seconds(60))
            return nil
        }
        let drawn = try #require(ImageRenderer(content: view).cgImage)
        let logo = try #require(SpecialtyArtwork.bundledLogo(for: nse))

        // The tile's text sits in the middle; the corners are bare accent color. Compare pixels, not encoded
        // bytes: repeated renders of text are not byte-identical.
        let corners = [(0.1, 0.1), (0.9, 0.1), (0.1, 0.9), (0.9, 0.9)]
        func isAccent(_ pixel: [UInt8]) -> Bool {
            abs(Int(pixel[0]) - accent.red) <= 8 && abs(Int(pixel[1]) - accent.green) <= 8 && abs(Int(pixel[2]) - accent.blue) <= 8
        }
        // Precondition: the bundled logo is distinguishable from the tile at the sampled points.
        let logoPixels = corners.map { logo.rgba(atX: Int(Double(logo.width) * $0.0), y: Int(Double(logo.height) * $0.1)) }
        try #require(logoPixels.contains { !isAccent($0) })

        for corner in corners {
            let pixel = drawn.rgba(atX: Int(Double(drawn.width) * corner.0), y: Int(Double(drawn.height) * corner.1))
            #expect(isAccent(pixel), "corner \(corner) drew \(pixel), not the tile's accent color")
        }
    }
}

private extension CGImage {
    /// The RGBA bytes of the pixel at (`x`, `y`), measured from the top-left, after drawing into an sRGB bitmap.
    func rgba(atX x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(self, in: CGRect(x: -x, y: -(height - 1 - y), width: width, height: height))
        return pixel
    }
}
#endif
