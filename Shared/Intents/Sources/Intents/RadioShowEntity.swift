//
//  RadioShowEntity.swift
//  Intents
//
//  A specialty program from the `GET /specialty-shows` catalog, modeled as an iOS 27 audio-schema
//  `radioShow` entity. Keyed by the program slug (stable, never reused), titled with the program
//  name. Distinct from `ShowEntity`, which is one DJ sign-on airing keyed by its ShowMarker id.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema): the schema symbols do not exist in earlier
//  SDKs, so this file compiles out there.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import AppIntents
import Foundation
import Playlist

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@AppEntity(schema: .audio.radioShow)
struct RadioShowEntity {
    static let defaultQuery = RadioShowEntityQuery()

    let id: String

    var title: String

    init(show: SpecialtyShow) {
        self.id = show.slug
        self.title = show.name
    }

    init(specialty: SpecialtyShowRef) {
        self.id = specialty.slug
        self.title = specialty.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    /// Resolves programs by slug from the catalog, or from a specialty the caller has already decoded.
    struct RadioShowEntityQuery: EntityQuery {
        /// One client for every default query, so its 5-minute cache is shared.
        private static let sharedClient = SpecialtyShowClient()

        private let catalog: @Sendable () async throws -> [SpecialtyShow]

        init() {
            self.init(catalog: { try await Self.sharedClient.shows() })
        }

        init(catalog: @escaping @Sendable () async throws -> [SpecialtyShow]) {
            self.catalog = catalog
        }

        func entities(for identifiers: [String]) async throws -> [RadioShowEntity] {
            let bySlug = Dictionary(
                try await catalog().map { ($0.slug, RadioShowEntity(show: $0)) },
                uniquingKeysWith: { first, _ in first }
            )
            return identifiers.compactMap { bySlug[$0] }
        }

        /// The program for `slug`. A `specialty` that carries the slug answers without the catalog,
        /// so a now-playing surface that decoded `on_air.specialty` needs no request.
        func entity(slug: String, specialty: SpecialtyShowRef?) async throws -> RadioShowEntity? {
            if let specialty, specialty.slug == slug {
                return RadioShowEntity(specialty: specialty)
            }
            return try await entities(for: [slug]).first
        }

        func suggestedEntities() async throws -> [RadioShowEntity] {
            try await catalog().map(RadioShowEntity.init(show:))
        }
    }
}
#endif
#endif
