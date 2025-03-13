//
//  ExponentialBackoffTimer.swift
//  Core
//
//  Created by Jake Bromberg on 3/1/25.
//

import Foundation

public struct ExponentialBackoff: CustomStringConvertible {
    // Tracks the number of connection attempts.
    public private(set) var numberOfAttempts: UInt = 0
    public private(set) var totalWaitTime: TimeInterval = 0.0
    
    let initialWaitTime: TimeInterval
    let maximumWaitTime: TimeInterval
    
    public init(initialWaitTime: TimeInterval = 0.25, maximumWaitTime: TimeInterval = 10.0) {
        self.initialWaitTime = initialWaitTime
        self.maximumWaitTime = maximumWaitTime
    }
    
    /// Returns the wait time for the next attempt.
    /// - Note: The first attempt returns 0.0 (i.e. immediate attempt).
    public mutating func nextWaitTime() -> TimeInterval {
        // For the first attempt, immediately return 0.0.
        if numberOfAttempts == 0 {
            numberOfAttempts += 1
            return 0.0
        }
        
        // Calculate the multiplier as 2^(numberOfAttempts - 1)
        let multiplier = pow(2.0, Double(numberOfAttempts - 1))
        let exponentialWaitTime = initialWaitTime * multiplier
        
        // Add a small random addition (between 0 and 1) to avoid synchronization issues.
        let randomWaitAddition = Double.random(in: 0..<1)
        let randomExponentialWaitTime = exponentialWaitTime + randomWaitAddition
        
        // Ensure the wait time is within the specified bounds.
        let finalWaitTime = min(max(0.0, randomExponentialWaitTime), maximumWaitTime)
        
        numberOfAttempts += 1
        totalWaitTime += finalWaitTime
        
        return finalWaitTime
    }
    
    /// Resets the attempt counter.
    public mutating func reset() {
        numberOfAttempts = 0
        totalWaitTime = 0
    }
    
    public var description: String {
        "(attempts: \(numberOfAttempts), totalWaitTime \(totalWaitTime))"
    }
}

public extension TimeInterval {
    var nanoseconds: UInt64 {
        UInt64(self * 1_000_000_000)
    }
}
