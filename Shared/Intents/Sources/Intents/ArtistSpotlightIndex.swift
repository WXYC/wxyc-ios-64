//
//  ArtistSpotlightIndex.swift
//  Intents
//
//  Name of the named Spotlight index every `ArtistEntity` donation targets.
//  Canonical home for the constant, mirroring `PlaycutSpotlightIndex`: the
//  C6 donation pipeline (`CoreSpotlightArtistIndexer` in AppServices, which
//  depends on WXYCIntents) reads it from here so it can never drift onto a
//  different index name than any future artist-side reindex handler.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum ArtistSpotlightIndex {
    public static let name = "wxyc.artists"
}
