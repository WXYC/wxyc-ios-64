//
//  DJEntityQuery.swift
//  Intents
//
//  AppEntity query for DJEntity, mirroring ArtistEntityQuery. F5b lands a
//  minimal, wireable shape: the injected source hands back show markers, and
//  `entities(for:)` derives one deduped DJEntity per normalized DJ name
//  (skipping markers with no DJ name) and resolves the requested
//  identifiers against that set.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist

public struct DJEntityQuery: EntityQuery {
    public typealias ShowMarkerSource = @Sendable () async -> [ShowMarker]

    private let source: ShowMarkerSource

    public init() {
        self.init(source: { [] })
    }

    public init(source: @escaping ShowMarkerSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities by deduping the source's show
    /// markers down to one DJEntity per normalized DJ name, then looking up
    /// each requested id. Preserves the input order and drops ids the source
    /// couldn't resolve, matching the AppIntents `entities(for:)` contract.
    /// See `EntityQueryResolution.swift` for the shared derived-by-
    /// normalization resolution this delegates to.
    public func entities(for identifiers: [DJID]) async throws -> [DJEntity] {
        await resolveEntities(identifiers: identifiers, from: source) { marker in
            marker.djName.map(DJEntity.init(djName:))
        }
    }

    public func suggestedEntities() async throws -> [DJEntity] {
        []
    }
}
