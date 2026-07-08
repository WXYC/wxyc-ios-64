//
//  PlaycutID.swift
//  Intents
//
//  Typed wrapper around Playcut's UInt64 id so it can serve as an AppEntity's
//  identifier. Wrapping (instead of retroactively conforming UInt64) prevents
//  cross-entity assignment (`let showID: ShowID = playcutEntity.id` won't
//  compile) and sets the identifier pattern for the F5 sibling entities.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation

public struct PlaycutID: Hashable, Sendable, Codable, LosslessStringConvertible, EntityIdentifierConvertible {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    public init?(_ description: String) {
        guard let value = UInt64(description) else { return nil }
        self.value = value
    }

    public var description: String {
        String(value)
    }

    public var entityIdentifierString: String {
        description
    }

    public static func entityIdentifier(for entityIdentifierString: String) -> PlaycutID? {
        PlaycutID(entityIdentifierString)
    }
}
//private extension UInt64: EntityIdentifierConvertible {
//    
//}
