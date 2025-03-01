//
//  CachedRecord.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/26/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation

struct CachedRecord<Value: Codable>: Codable {
    let value: Value
    let timestamp: TimeInterval
    let lifespan: TimeInterval
    
    // Before you're tempted to say, "Swift autosynthesizes initializers on structs, let's blow this away," let me tell you
    // this: I put this here as a fix to a compiler bug that overrode the timestamp on serialized records. Beware.
    init(value: Value, timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate, lifespan: TimeInterval) {
        self.value = value
        self.timestamp = timestamp
        self.lifespan = lifespan
    }
    
    var isExpired: Bool {
        return Date.timeIntervalSinceReferenceDate - self.timestamp > self.lifespan
    }
}
