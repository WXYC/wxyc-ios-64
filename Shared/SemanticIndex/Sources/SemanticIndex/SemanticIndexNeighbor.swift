//
//  SemanticIndexNeighbor.swift
//  SemanticIndex
//
//  A neighbor entry from the semantic-index neighbors endpoint. Represents
//  a DJ-validated transition between two artists in the WXYC flowsheet graph.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A neighbor entry from the semantic-index neighbors endpoint.
///
/// Each neighbor represents an artist that WXYC DJs have historically
/// transitioned to or from the source artist. The `weight` reflects
/// how strong the transition relationship is, and `detail` provides
/// the underlying statistics.
public struct SemanticIndexNeighbor: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { artist.id }

    public let artist: SemanticIndexArtist
    public let weight: Double
    public let detail: TransitionDetail?

    public init(artist: SemanticIndexArtist, weight: Double, detail: TransitionDetail? = nil) {
        self.artist = artist
        self.weight = weight
        self.detail = detail
    }

    /// Statistics underlying a DJ transition relationship.
    public struct TransitionDetail: Codable, Sendable, Hashable {
        public let rawCount: Int
        public let pmi: Double

        public init(rawCount: Int, pmi: Double) {
            self.rawCount = rawCount
            self.pmi = pmi
        }

        private enum CodingKeys: String, CodingKey {
            case rawCount = "raw_count"
            case pmi
        }
    }
}
