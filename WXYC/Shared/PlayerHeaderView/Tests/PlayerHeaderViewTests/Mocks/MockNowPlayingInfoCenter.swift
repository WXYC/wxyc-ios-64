//
//  MockNowPlayingInfoCenter.swift
//  PlayerHeaderViewTests
//
//  Mock implementation of NowPlayingInfoCenterProtocol for testing
//

import Foundation
import MediaPlayer
@testable import PlayerHeaderView
@testable import Playback

/// Mock now playing info center for testing
public final class MockNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {
    
    // MARK: - State Tracking
    
    public var nowPlayingInfoSetCount = 0
    public var playbackStateSetCount = 0
    
    // MARK: - NowPlayingInfoCenterProtocol
    
    public var nowPlayingInfo: [String: Any]? {
        didSet {
            nowPlayingInfoSetCount += 1
        }
    }
    
    public var playbackState: MPNowPlayingPlaybackState = .unknown {
        didSet {
            playbackStateSetCount += 1
        }
    }
    
    public init() {}
    
    // MARK: - Test Helpers
    
    public func reset() {
        nowPlayingInfo = nil
        playbackState = .unknown
        nowPlayingInfoSetCount = 0
        playbackStateSetCount = 0
    }
    
    /// Check if a specific key exists in nowPlayingInfo
    public func hasKey(_ key: String) -> Bool {
        return nowPlayingInfo?[key] != nil
    }
    
    /// Get a value from nowPlayingInfo
    public func getValue<T>(for key: String) -> T? {
        return nowPlayingInfo?[key] as? T
    }
}
