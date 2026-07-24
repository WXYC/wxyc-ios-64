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
    /// returns duplicate ids the first one wins — the query never traps.
    public func entities(for identifiers: [ShowID]) async throws -> [ShowEntity] {
        let rawIDs = identifiers.map(\.value)
        let markers = await source(rawIDs)
        let byID = Dictionary(
            markers.map { ($0.id, ShowEntity(start: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        return rawIDs.compactMap { byID[$0] }
    }

    public func suggestedEntities() async throws -> [ShowEntity] {
        []
    }
}
