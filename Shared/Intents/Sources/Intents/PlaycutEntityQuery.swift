//
//  PlaycutEntityQuery.swift
//  Intents
//
//  AppEntity query for PlaycutEntity. F1 lands a wireable shape with an
//  injectable source and safe empty defaults; reindex handler bodies and
//  the production source binding follow in F3.
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

    public func entities(for identifiers: [PlaycutID]) async throws -> [PlaycutEntity] {
        let playcuts = await source(identifiers.map(\.value))
        return playcuts.map(PlaycutEntity.init(playcut:))
    }

    public func suggestedEntities() async throws -> [PlaycutEntity] {
        []
    }
}
