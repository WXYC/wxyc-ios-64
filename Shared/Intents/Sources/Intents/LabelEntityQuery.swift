//
//  LabelEntityQuery.swift
//  Intents
//
//  AppEntity query for LabelEntity. F5d lands a minimal, wireable shape: the
//  injected source hands back the playcut cache, and `entities(for:)` derives
//  one deduped LabelEntity per normalized label name (dropping playcuts with
//  no `labelName`) and resolves the requested identifiers against that set.
//  Donation and a richer per-label query (search-by-name, suggestions) are
//  deferred.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist

public struct LabelEntityQuery: EntityQuery {
    public typealias PlaycutSource = @Sendable () async -> [Playcut]

    private let source: PlaycutSource

    public init() {
        self.init(source: { [] })
    }

    public init(source: @escaping PlaycutSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities by deduping the source's playcuts
    /// down to one LabelEntity per normalized label name, then looking up
    /// each requested id. Preserves the input order and drops ids the source
    /// couldn't resolve, matching the AppIntents `entities(for:)` contract.
    /// See `EntityQueryResolution.swift` for the shared derived-by-
    /// normalization resolution this delegates to.
    public func entities(for identifiers: [LabelID]) async throws -> [LabelEntity] {
        await resolveEntities(identifiers: identifiers, from: source) { playcut in
            playcut.labelName.map(LabelEntity.init(labelName:))
        }
    }

    public func suggestedEntities() async throws -> [LabelEntity] {
        []
    }
}
