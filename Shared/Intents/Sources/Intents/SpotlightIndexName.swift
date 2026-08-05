//
//  SpotlightIndexName.swift
//  Intents
//
//  Canonical home for every named Spotlight index's `CSSearchableIndex`
//  name (#758). Collapses three near-identical single-purpose enums
//  (`PlaycutSpotlightIndex`, `ArtistSpotlightIndex`, `ConcertSpotlightIndex`
//  — each holding one `name` string) into one namespace: the F2 donation
//  pipelines (`CoreSpotlightEntityIndexer` instantiations in AppServices,
//  which depends on WXYCIntents) and the F3 `IndexedEntityQuery` reindex
//  handlers declared in this package both read the relevant constant from
//  here, so a given entity kind's donation and reindex paths can never drift
//  onto different index names. A fourth entity kind's index name is a new
//  `static let` here, not a new enum type.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum SpotlightIndexName {
    /// Name of the WXYC playcut index.
    public static let playcuts = "wxyc.playcuts"

    /// Name of the WXYC artist index.
    public static let artists = "wxyc.artists"

    /// Name of the WXYC concert index.
    public static let concerts = "wxyc.concerts"
}
