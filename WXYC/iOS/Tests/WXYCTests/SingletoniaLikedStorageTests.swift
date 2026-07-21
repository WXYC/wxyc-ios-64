//
//  SingletoniaLikedStorageTests.swift
//  WXYC
//
//  Verifies the `-marketing` recording's likes-store selection: under
//  `-marketing` (DEBUG only) likes route to an in-memory store so a seeded like
//  never writes `liked-songs.json` on a simulator someone also uses by hand;
//  production always gets the durable Application Support file. The launch-arg
//  check itself isn't testable (`MarketingModeController.isEnabled` is a cached
//  `static let`), so the decision is factored into this pure, parameterized
//  helper and tested directly.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import LikedSongs
import Testing
@testable import WXYC

@MainActor
@Suite("Singletonia liked-songs storage selection")
struct SingletoniaLikedStorageTests {
    @Test("Marketing mode routes likes to an in-memory store")
    func marketingUsesInMemoryStorage() {
        let storage = Singletonia.likedStorage(isMarketing: true)
        #expect(storage is MarketingLikedStorage)
    }

    @Test("Production routes likes to the durable Application Support store")
    func productionUsesDurableStorage() {
        let storage = Singletonia.likedStorage(isMarketing: false)
        #expect(storage is LikedSongs.AppSupportFileStorage)
    }
}
