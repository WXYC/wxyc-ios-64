//
//  PosterGradientTests.swift
//  Concerts
//
//  Tests for the deterministic poster-gradient seed used when a concert has no
//  `image_url` (the common case today). The seed must be stable across runs and
//  devices — never Swift's per-run-seeded `hashValue` — so the same concert
//  always paints the same gradient. The fold is verified against the published
//  64-bit FNV-1a test vectors.
//
//  Created by Jake Bromberg on 07/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

@Suite("PosterGradient")
struct PosterGradientTests {

    // MARK: - Canonical FNV-1a (hand-verifiable against published vectors)

    @Test("Matches the published 64-bit FNV-1a test vectors", arguments: [
        ("", UInt64(0xcbf29ce484222325)),
        ("a", UInt64(0xaf63dc4c8601ec8c)),
        ("foobar", UInt64(0x85944171f73967e8)),
    ])
    func fnv1aKnownVectors(input: String, expected: UInt64) {
        #expect(PosterGradient.fnv1a(input) == expected)
    }

    // MARK: - Palette selection

    @Test("The palette is non-empty so an index always resolves")
    func paletteNonEmpty() {
        #expect(!PosterGradient.palette.isEmpty)
    }

    @Test("Selects a palette pair deterministically for a concert")
    func deterministicForConcert() {
        let concert = Concert.stub()
        // Calling twice yields the identical pair — no per-run variation.
        #expect(PosterGradient.pair(for: concert) == PosterGradient.pair(for: concert))
    }

    @Test("The index is a pure fold over venue slug + id (run-stable)")
    func indexIsFoldOfSlugAndID() {
        let concert = Concert.stub(id: 4821, venue: .stub(slug: "cats-cradle"))
        // The seed is exactly "<slug>-<id>"; recomputing the canonical fold and
        // reducing mod the palette count must match `index(for:)`. This fails
        // loudly if anyone swaps the fold for `hashValue`.
        let expected = Int(PosterGradient.fnv1a("cats-cradle-4821") % UInt64(PosterGradient.palette.count))
        #expect(PosterGradient.index(for: concert) == expected)
    }

    @Test("The chosen pair is the palette entry at the computed index")
    func pairMatchesIndex() {
        let concert = Concert.stub()
        #expect(PosterGradient.pair(for: concert) == PosterGradient.palette[PosterGradient.index(for: concert)])
    }

    @Test("Different seeds generally land on different pairs")
    func differentSeedsDiffer() {
        // Not a hard collision guarantee, but two obviously different concerts
        // should not share an index by construction here.
        let a = Concert.stub(id: 1, venue: .stub(slug: "cats-cradle"))
        let b = Concert.stub(id: 2, venue: .stub(slug: "motorco"))
        #expect(PosterGradient.index(for: a) != PosterGradient.index(for: b))
    }
}
