//
//  SingletoniaMarketingStorageTests.swift
//  WXYC
//
//  Verifies the cross-store invariant `MarketingFileStorage` claims in prose
//  (WXYC/iOS/Marketing/MarketingFileStorage.swift): the likes and
//  dismissed-concerts factories each construct their own instance under
//  `-marketing`, so the two in-memory stores never share bytes. This is
//  orthogonal to `SingletoniaLikedStorageTests`/
//  `SingletoniaDismissedConcertsStorageTests`, which each verify a single
//  factory in isolation and can't see the other factory's result.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@MainActor
@Suite("Singletonia marketing storage isolation")
struct SingletoniaMarketingStorageTests {
    @Test("The marketing likes store and marketing dismissed-concerts store are distinct instances")
    func marketingStoresAreDistinctInstances() throws {
        let likedStorage = try #require(Singletonia.likedStorage(isMarketing: true) as? MarketingFileStorage)
        let dismissedStorage = try #require(Singletonia.dismissedConcertsStorage(isMarketing: true) as? MarketingFileStorage)
        #expect(likedStorage !== dismissedStorage)
    }
}
