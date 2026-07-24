//
//  ConcertSpotlightIndex.swift
//  Intents
//
//  Name of the named Spotlight index every `ConcertEntity` donation and
//  eviction targets. Canonical home for the constant, mirroring
//  `PlaycutSpotlightIndex`/`ArtistSpotlightIndex`: the OT-F2 donation
//  pipeline (`CoreSpotlightConcertIndexer` in AppServices, which depends on
//  WXYCIntents) reads it from here so it can never drift onto a different
//  index name than any future OT-F3 reindex handler declared in this
//  package.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum ConcertSpotlightIndex {
    public static let name = "wxyc.concerts"
}
