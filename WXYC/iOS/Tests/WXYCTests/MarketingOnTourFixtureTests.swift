//
//  MarketingOnTourFixtureTests.swift
//  WXYC
//
//  Locks in the `-marketing` recording's dependency on `Concert.previewList`:
//  `Singletonia.marketingHeroConcertID` is derived from `previewList.first`, so
//  a future edit to the fixture — made purely to tweak the Xcode canvas
//  preview — that drops the bio or reorders entries would otherwise silently
//  break the recorded "About the Artist" scene with no compiler or test signal.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Testing
@testable import WXYC

@Suite("Marketing mode On Tour fixture")
struct MarketingOnTourFixtureTests {
    @Test("The fixture's first concert — the one the marketing sequence opens — has an artist bio")
    func firstConcertHasArtistBio() {
        let bio = Concert.previewList.first?.artistBio
        #expect(bio != nil && !(bio ?? "").isEmpty)
    }
}
