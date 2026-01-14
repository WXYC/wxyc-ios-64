//
//  MockRemoteCommandCenter.swift
//  Playback
//
//  Mock implementation of RemoteCommandCenterProtocol for testing
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import MediaPlayer
@testable import Playback

/// Mock remote command for testing
public final class MockRemoteCommand: RemoteCommandProtocol {
    public var isEnabled: Bool = false
    public var targetHandlers: [(MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus] = []
    public var targets: [Any] = []
    
    public init() {}
    
    public func addTarget(handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any {
        targetHandlers.append(handler)
        let target = NSObject()
        targets.append(target)
        return target
    }
    
    public func removeTarget(_ target: Any?) {
        guard let target = target else { return }
        if let index = targets.firstIndex(where: { ($0 as AnyObject) === (target as AnyObject) }) {
            targets.remove(at: index)
            if index < targetHandlers.count {
                targetHandlers.remove(at: index)
            }
        }
    }
    
    /// Simulate triggering the command
    
    public func reset() {
        isEnabled = false
        targetHandlers.removeAll()
        targets.removeAll()
    }
}

/// Mock remote command center for testing
public final class MockRemoteCommandCenter: RemoteCommandCenterProtocol {

    public let playCommand: RemoteCommandProtocol
    public let pauseCommand: RemoteCommandProtocol
    public let stopCommand: RemoteCommandProtocol
    public let togglePlayPauseCommand: RemoteCommandProtocol
    public let skipForwardCommand: RemoteCommandProtocol
    public let skipBackwardCommand: RemoteCommandProtocol
    public let nextTrackCommand: RemoteCommandProtocol
    public let previousTrackCommand: RemoteCommandProtocol
    public let seekForwardCommand: RemoteCommandProtocol
    public let seekBackwardCommand: RemoteCommandProtocol
    public let changePlaybackPositionCommand: RemoteCommandProtocol

    private let _playCommand = MockRemoteCommand()
    private let _pauseCommand = MockRemoteCommand()
    private let _stopCommand = MockRemoteCommand()
    private let _togglePlayPauseCommand = MockRemoteCommand()
    private let _skipForwardCommand = MockRemoteCommand()
    private let _skipBackwardCommand = MockRemoteCommand()
    private let _nextTrackCommand = MockRemoteCommand()
    private let _previousTrackCommand = MockRemoteCommand()
    private let _seekForwardCommand = MockRemoteCommand()
    private let _seekBackwardCommand = MockRemoteCommand()
    private let _changePlaybackPositionCommand = MockRemoteCommand()

    public init() {
        playCommand = _playCommand
        pauseCommand = _pauseCommand
        stopCommand = _stopCommand
        togglePlayPauseCommand = _togglePlayPauseCommand
        skipForwardCommand = _skipForwardCommand
        skipBackwardCommand = _skipBackwardCommand
        nextTrackCommand = _nextTrackCommand
        previousTrackCommand = _previousTrackCommand
        seekForwardCommand = _seekForwardCommand
        seekBackwardCommand = _seekBackwardCommand
        changePlaybackPositionCommand = _changePlaybackPositionCommand
    }

    // MARK: - Test Helpers

    /// Access to concrete mock commands for assertions
    public var mockPlayCommand: MockRemoteCommand { _playCommand }
    public var mockPauseCommand: MockRemoteCommand { _pauseCommand }
    public var mockStopCommand: MockRemoteCommand { _stopCommand }
    public var mockTogglePlayPauseCommand: MockRemoteCommand { _togglePlayPauseCommand }
    public var mockSkipForwardCommand: MockRemoteCommand { _skipForwardCommand }
    public var mockSkipBackwardCommand: MockRemoteCommand { _skipBackwardCommand }

    public func reset() {
        _playCommand.reset()
        _pauseCommand.reset()
        _stopCommand.reset()
        _togglePlayPauseCommand.reset()
        _skipForwardCommand.reset()
        _skipBackwardCommand.reset()
        _nextTrackCommand.reset()
        _previousTrackCommand.reset()
        _seekForwardCommand.reset()
        _seekBackwardCommand.reset()
        _changePlaybackPositionCommand.reset()
    }
}
