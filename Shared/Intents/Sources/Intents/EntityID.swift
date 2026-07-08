//
//  EntityID.swift
//  Intents
//
//  Phantom-typed identifier wrapper shared by every WXYC AppEntity. The `Owner`
//  parameter has no runtime representation — it only exists to make
//  `EntityID<PlaycutEntity>` and `EntityID<ShowEntity>` distinct types so
//  cross-entity id assignment (`let showID: ShowID = playcutEntity.id`) fails
//  to compile. Each entity file adds a `typealias FooID = EntityID<FooEntity>`.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation

public struct EntityID<Owner>: Hashable, Codable, CustomStringConvertible, EntityIdentifierConvertible {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    public var description: String {
        String(value)
    }

    public var entityIdentifierString: String {
        description
    }

    public static func entityIdentifier(for entityIdentifierString: String) -> Self? {
        UInt64(entityIdentifierString).map(Self.init)
    }
}

extension EntityID: Sendable where Owner: Sendable { }
