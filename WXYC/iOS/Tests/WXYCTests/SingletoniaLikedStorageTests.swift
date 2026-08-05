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

import Core
import Foundation
import Testing
@testable import WXYC

@MainActor
@Suite("Singletonia liked-songs storage selection")
struct SingletoniaLikedStorageTests {
    @Test("Marketing mode routes likes to an in-memory store")
    func marketingUsesInMemoryStorage() {
        let storage = Singletonia.likedStorage(isMarketing: true)
        #expect(storage is MarketingFileStorage)
    }

    @Test("Production routes likes to the durable Application Support store")
    func productionUsesDurableStorage() throws {
        let storage = Singletonia.likedStorage(isMarketing: false)
        let appSupportStorage = try #require(storage as? AppSupportFileStorage)
        // Pinning the filename, not just the type, matters: `LikedSongsStore`
        // and `DismissedConcertsStore` both resolve to `AppSupportFileStorage`,
        // so a type-only check can't catch the two factories being swapped and
        // pointed at each other's file.
        #expect(appSupportStorage.fileURL.lastPathComponent == "liked-songs.json")
    }
}
