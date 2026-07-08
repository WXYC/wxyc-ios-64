//
//  PlaycutEntityQuery.swift
//  Intents
//
//  AppEntity query for PlaycutEntity. F1 lands a wireable shape with an
//  injectable source and safe empty defaults; reindex handlers and the
//  production source binding follow in F3.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist

public struct PlaycutEntityQuery: EntityQuery {
    public typealias PlaycutSource = @Sendable ([Playcut.ID]) async -> [Playcut]

    private let source: PlaycutSource

    public init() {
        self.init(source: { _ in [] })
    }

    public init(source: @escaping PlaycutSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities via the injected source. The result
    /// preserves the input order and drops ids the source couldn't resolve,
    /// matching the AppIntents `entities(for:)` contract. If the source
    /// returns duplicate ids the first one wins — the query never traps.
    public func entities(for identifiers: [PlaycutID]) async throws -> [PlaycutEntity] {
        let rawIDs = identifiers.map(\.value)
        let playcuts = await source(rawIDs)
        let byID = Dictionary(
            playcuts.map { ($0.id, PlaycutEntity(playcut: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        return rawIDs.compactMap { byID[$0] }
    }

    public func suggestedEntities() async throws -> [PlaycutEntity] {
        []
    }
}
