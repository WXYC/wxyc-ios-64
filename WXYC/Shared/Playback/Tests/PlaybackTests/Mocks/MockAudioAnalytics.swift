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
final class MockAudioAnalytics: AudioAnalyticsProtocol, @unchecked Sendable {
    
    // MARK: - Call Tracking
    
    var playCallCount = 0
    var lastPlaySource: String?
    var lastPlayReason: String?
    
    var pauseCallCount = 0
    var lastPauseSource: String?
    var lastPauseDuration: TimeInterval?
    var lastPauseReason: String?
    
    var captureErrorCallCount = 0
    var lastCapturedError: Error?
    var lastCapturedContext: String?
    
    // MARK: - AudioAnalyticsProtocol
    
    init() {}
    
    func play(source: String, reason: String) {
        playCallCount += 1
        lastPlaySource = source
        lastPlayReason = reason
    }
    
    func pause(source: String, duration: TimeInterval) {
        pauseCallCount += 1
        lastPauseSource = source
        lastPauseDuration = duration
        lastPauseReason = nil
    }
    
    func pause(source: String, duration: TimeInterval, reason: String) {
        pauseCallCount += 1
        lastPauseSource = source
        lastPauseDuration = duration
        lastPauseReason = reason
    }
    
    func capture(error: Error, context: String) {
        captureErrorCallCount += 1
        lastCapturedError = error
        lastCapturedContext = context
    }
    
    // MARK: - Test Helpers
    
    func reset() {
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

