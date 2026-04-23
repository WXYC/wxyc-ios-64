//
//  RecommendedArtist.swift
//  WXYC
//
//  Navigation value for pushing to an ArtistDetailView from a WXYC
//  Recommends section. Carries the minimal data needed to display
//  the artist detail screen.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A recommended artist used as a navigation destination value.
///
/// Contains the semantic-index artist ID, canonical name, and genre.
/// Conforms to `Hashable` for use with `navigationDestination(for:)`.
struct RecommendedArtist: Hashable {
    let id: Int
    let name: String
    let genre: String?
}
