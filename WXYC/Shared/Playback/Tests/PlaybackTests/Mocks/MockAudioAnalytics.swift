//
//  MockAudioAnalytics.swift
//  StreamingAudioPlayerTests
//
//  Mock implementation of AudioAnalyticsProtocol for testing
//

import Foundation
import Analytics
@testable import Playback

/// Mock analytics tracker for testing
public final class MockAudioAnalytics: AudioAnalyticsProtocol, @unchecked Sendable {
    
    // MARK: - Call Tracking
    
    public var playCallCount = 0
    public var lastPlaySource: String?
    public var lastPlayReason: String?
    
    public var pauseCallCount = 0
    public var lastPauseSource: String?
    public var lastPauseDuration: TimeInterval?
    public var lastPauseReason: String?
    
    public var captureErrorCallCount = 0
    public var lastCapturedError: Error?
    public var lastCapturedContext: String?
    
    // MARK: - AudioAnalyticsProtocol
    
    public init() {}
    
    public func play(source: String, reason: String) {
        playCallCount += 1
        lastPlaySource = source
        lastPlayReason = reason
    }
    
    public func pause(source: String, duration: TimeInterval) {
        pauseCallCount += 1
        lastPauseSource = source
        lastPauseDuration = duration
        lastPauseReason = nil
    }
    
    public func pause(source: String, duration: TimeInterval, reason: String) {
        pauseCallCount += 1
        lastPauseSource = source
        lastPauseDuration = duration
        lastPauseReason = reason
    }
    
    public func capture(error: Error, context: String) {
        captureErrorCallCount += 1
        lastCapturedError = error
        lastCapturedContext = context
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
        playCallCount = 0
        lastPlaySource = nil
        lastPlayReason = nil
        
        pauseCallCount = 0
        lastPauseSource = nil
        lastPauseDuration = nil
        lastPauseReason = nil
        
        captureErrorCallCount = 0
        lastCapturedError = nil
        lastCapturedContext = nil
    }
}

