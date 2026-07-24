//
//  PlaycutReindexer.swift
//  Intents
//
//  Donation seam through which the F3 `IndexedEntityQuery` reindex handlers
//  (`PlaycutEntityQuery+IndexedEntityQuery.swift`) re-donate `PlaycutEntity`
//  values to Spotlight. Declared here rather than alongside the production
//  `CoreSpotlightIndexer` in AppServices because `PlaycutEntityQuery` needs a
//  seam it can request via `@Dependency`, and AppServices depends on
//  WXYCIntents — not the other way around. `CoreSpotlightIndexer` conforms to
//  this protocol (in addition to its existing `SpotlightIndexer` conformance)
//  so the F2 donation pipeline and the F3 reindex handlers share one indexer
//  instance and one named index.
//
//  Free of CoreSpotlight and AppIntents `IndexedEntity` symbols so it compiles
//  on every platform WXYCIntents ships to, including watchOS and tvOS, where
//  CoreSpotlight is unavailable.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Name of the named Spotlight index every playcut donation and reindex path
/// targets. Canonical home for the constant: both the F3 reindex handlers
/// (this package) and the F2 donation pipeline (`CoreSpotlightIndexer` in
/// AppServices, which depends on WXYCIntents) read it from here so the two
/// paths can never drift onto different index names.
public enum PlaycutSpotlightIndex {
    public static let name = "wxyc.playcuts"
}

/// Donates re-indexed `PlaycutEntity` values back to Spotlight.
///
/// `CoreSpotlightIndexer` (AppServices) is the production conformer; tests use
/// a recording spy.
public protocol PlaycutReindexer: Sendable {
    func donate(_ entities: [PlaycutEntity]) async throws
}
