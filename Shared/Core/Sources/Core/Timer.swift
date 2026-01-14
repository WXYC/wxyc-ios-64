//
//  Timer.swift
//  Core
//
//  Simple elapsed time measurement utility for performance logging.
//
//  Created by Jake Bromberg on 03/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

public struct Timer: Sendable {
    public static func start() -> Timer {
        return Timer()
    }
    
    public func duration() -> TimeInterval {
        let end = Date.now.timeIntervalSince1970
        return end - start
    }
    
    let start: TimeInterval = Date.now.timeIntervalSince1970
    
    private init() { }
}
