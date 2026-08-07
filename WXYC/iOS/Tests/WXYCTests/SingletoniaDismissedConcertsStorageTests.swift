//
//  SingletoniaDismissedConcertsStorageTests.swift
//  WXYC
//
//  Verifies the `-marketing` recording's dismissed-concerts-store selection:
//  under `-marketing` (DEBUG only) dismissals route to an in-memory store so a
//  recording can never read or overwrite `dismissed-concerts.json` on a
//  simulator someone also uses by hand; production always gets the durable
//  Application Support file. Mirrors `SingletoniaLikedStorageTests` — the pure,
//  parameterized helper is tested directly, since the launch-arg check itself
//  isn't testable (`MarketingModeController.isEnabled` is a cached `static let`).
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Testing
@testable import WXYC

@MainActor
@Suite("Singletonia dismissed-concerts storage selection")
struct SingletoniaDismissedConcertsStorageTests {
    @Test("Marketing mode routes dismissals to an in-memory store")
    func marketingUsesInMemoryStorage() {
        let storage = Singletonia.dismissedConcertsStorage(isMarketing: true)
        #expect(storage is MarketingFileStorage)
    }

    @Test("Production routes dismissals to the durable Application Support store")
    func productionUsesDurableStorage() throws {
        let storage = Singletonia.dismissedConcertsStorage(isMarketing: false)
        let appSupportStorage = try #require(storage as? AppSupportFileStorage)
        // Pinning the filename, not just the type, matters: `LikedSongsStore`
        // and `DismissedConcertsStore` both resolve to `AppSupportFileStorage`,
        // so a type-only check can't catch the two factories being swapped and
        // pointed at each other's file.
        #expect(appSupportStorage.fileURL.lastPathComponent == "dismissed-concerts.json")
    }
}
