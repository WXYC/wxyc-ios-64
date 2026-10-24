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
import Playlist
@testable import Artwork

private func program(slug: String, squareURL: URL? = nil) -> SpecialtyShowRef {
    SpecialtyShowRef(
        id: 7, slug: slug, name: "Show", shortName: "SH",
        artwork: squareURL.map { .init(squareURL: $0) }
    )
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
