//
//  MockAudioSession.swift
//  Playback
//
//  Mock implementation of AudioSessionProtocol for testing
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
@testable import Playback

#if os(iOS) || os(tvOS) || os(watchOS)

/// Mock audio session for testing (iOS/tvOS/watchOS)
public final class MockAudioSession: AudioSessionProtocol {

    // MARK: - State Tracking

    public var setCategoryCallCount = 0
    public var setActiveCallCount = 0

    public var lastCategory: AVAudioSession.Category?
    public var lastMode: AVAudioSession.Mode?
    public var lastCategoryOptions: AVAudioSession.CategoryOptions?
    public var lastActiveState: Bool?
    public var lastActiveOptions: AVAudioSession.SetActiveOptions?

    public var shouldThrowOnSetCategory = false
    public var shouldThrowOnSetActive = false
    
    public init() {}

    // MARK: - AudioSessionProtocol

    public func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        setCategoryCallCount += 1
        lastCategory = category
        lastMode = mode
        lastCategoryOptions = options

        if shouldThrowOnSetCategory {
            throw MockAudioSessionError.setCategoryFailed
        }
    }

    public func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        setActiveCallCount += 1
        lastActiveState = active
        lastActiveOptions = options

        if shouldThrowOnSetActive {
            throw MockAudioSessionError.setActiveFailed
        }
    }

    public var currentRoute: AVAudioSessionRouteDescription {
        // Return the shared instance's route for basic compatibility
        // In tests, we typically don't care about the actual route
        AVAudioSession.sharedInstance().currentRoute
    }

    // MARK: - Test Helpers

    public func reset() {
        setCategoryCallCount = 0
        setActiveCallCount = 0
        lastCategory = nil
        lastMode = nil
        lastCategoryOptions = nil
        lastActiveState = nil
        lastActiveOptions = nil
        shouldThrowOnSetCategory = false
        shouldThrowOnSetActive = false
    }
}

#else

/// Mock audio session for testing (macOS)
public final class MockAudioSession: AudioSessionProtocol {
    
    // MARK: - State Tracking
    
    public var setActiveCallCount = 0
    public var lastActiveState: Bool?
    public var shouldThrowOnSetActive = false
        
    public init() {}
    
    // MARK: - AudioSessionProtocol
    
    public func setActive(_ active: Bool) throws {
        setActiveCallCount += 1
        lastActiveState = active
        
        if shouldThrowOnSetActive {
            throw MockAudioSessionError.setActiveFailed
        }
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
        setActiveCallCount = 0
        lastActiveState = nil
        shouldThrowOnSetActive = false
    }
}

#endif

public enum MockAudioSessionError: Error {
    case setCategoryFailed
    case setActiveFailed
}
