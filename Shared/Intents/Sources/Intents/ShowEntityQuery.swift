//
//  ShowEntityQuery.swift
//  Intents
//
//  AppEntity query for ShowEntity, mirroring `PlaycutEntityQuery`. Lands a
//  wireable shape with an injectable source and safe empty defaults; the
//  production source binding and reindex handlers are a later slice.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist

public struct ShowEntityQuery: EntityQuery {
    public typealias ShowSource = @Sendable ([UInt64]) async -> [ShowMarker]

    private let source: ShowSource

    public init() {
        self.init(source: { _ in [] })
    }

    public init(source: @escaping ShowSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities via the injected source. The result
    /// preserves the input order and drops ids the source couldn't resolve,
    /// matching the AppIntents `entities(for:)` contract. If the source
    /// returns duplicate ids the first one wins — the query never traps. See
    /// `EntityQueryResolution.swift` for the shared keyed-by-backend-id
    /// resolution this delegates to.
    public func entities(for identifiers: [ShowID]) async throws -> [ShowEntity] {
        await resolveEntities(
            identifiers: identifiers,
            rawID: { $0.value },
            from: source,
            id: \.id,
            makeEntity: { ShowEntity(start: $0) }
        )
    }

    public func suggestedEntities() async throws -> [ShowEntity] {
        []
    }
}
