//
//  Timer.swift
//  Core
//
//  Created by Jake Bromberg on 3/2/25.
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
