//
//  ArtworkLoaderStateTests.swift
//  Artwork
//
//  Platform-agnostic tests for ArtworkLoader.State. These run on the macOS host
//  too (unlike ArtworkLoaderTests, which is UIKit-gated), so they prove
//  ArtworkLoader compiles into the macOS build after its Core.Image migration.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Artwork

@Suite("ArtworkLoader.State")
struct ArtworkLoaderStateTests {

    @Test("unloaded is not loaded")
    func unloadedIsNotLoaded() {
        #expect(ArtworkLoader.State.unloaded.isLoaded == false)
    }

    @Test("failed is not loaded")
    func failedIsNotLoaded() {
        #expect(ArtworkLoader.State.failed.isLoaded == false)
    }

    @Test("notOnDiscogs carries its note and compares by note")
    func notOnDiscogsCarriesNote() {
        #expect(ArtworkLoader.State.notOnDiscogs(note: "embargo").isLoaded == false)
        #expect(ArtworkLoader.State.notOnDiscogs(note: "embargo") == .notOnDiscogs(note: "embargo"))
        #expect(ArtworkLoader.State.notOnDiscogs(note: "embargo") != .notOnDiscogs(note: "other"))
    }
}
