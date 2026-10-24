//
//  SpecialtyShowRefStubTests.swift
//  Playlist
//
//  Pins the defaults and named fixtures of `SpecialtyShowRef.stub` so that tests relying on them
//  fail here, in one place, rather than in a dozen consumers.
//
//  Created by Jake Bromberg on 10/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaylistTesting
@testable import Playlist

@Suite("SpecialtyShowRef.stub")
struct SpecialtyShowRefStubTests {

    @Test("The defaults describe a plain program with no tagline, accent color or logo")
    func defaults() {
        let program = SpecialtyShowRef.stub()
        #expect(program.id == 3)
        #expect(program.slug == "hogwash")
        #expect(program.name == "Hogwash")
        #expect(program.shortName == "HW")
        #expect(program.tagline == nil)
        #expect(program.accentColor == nil)
        #expect(program.artwork == nil)
        #expect(program.logsPlaycuts == nil)
    }

    @Test("A squareURL becomes the program's logo artwork")
    func squareURLBecomesArtwork() {
        let url = URL(string: "https://example.com/logo.png")!
        #expect(SpecialtyShowRef.stub(squareURL: url).artwork == .init(squareURL: url))
    }

    @Test("The tagged fixture has a tagline and accent color but no logo")
    func taggedFixture() {
        let program = SpecialtyShowRef.taggedStub
        #expect(program.tagline == "Weird and wonderful")
        #expect(program.accentColor == "#B3261E")
        #expect(program.artwork == nil)
    }

    @Test("The logo fixture has a logo URL")
    func logoFixture() {
        #expect(SpecialtyShowRef.logoStub.artwork?.squareURL == URL(string: "https://example.com/backyard-bbq.png"))
    }

    @Test("The untagged fixture has neither tagline nor short name")
    func untaggedFixture() {
        let program = SpecialtyShowRef.untaggedStub
        #expect(program.tagline == nil)
        #expect(program.shortName == nil)
    }

    @Test("Fixtures have distinct ids and slugs, and none uses a bundled-logo slug")
    func fixturesAreDistinct() {
        let all = [SpecialtyShowRef.taggedStub, .logoStub, .untaggedStub]
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.slug)).count == all.count)
        #expect(!all.contains { $0.slug == "new-science-experience" || $0.slug == "nse" })
    }
}
