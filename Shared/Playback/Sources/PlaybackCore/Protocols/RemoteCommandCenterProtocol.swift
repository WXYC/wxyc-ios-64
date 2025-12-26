//
//  RemoteCommandCenterProtocol.swift
//  StreamingAudioPlayer
//
//  Protocol for remote command center abstraction (wraps MPRemoteCommandCenter)
//

import Foundation
import MediaPlayer

/// Result type for remote command handlers

/// Protocol defining a single remote command
public protocol RemoteCommandProtocol: AnyObject {
    var isEnabled: Bool { get set }
    func addTarget(handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any
    func removeTarget(_ target: Any?)
}

/// Protocol defining the remote command center interface for testability
public protocol RemoteCommandCenterProtocol: AnyObject {
    var playCommand: RemoteCommandProtocol { get }
    var pauseCommand: RemoteCommandProtocol { get }
    var stopCommand: RemoteCommandProtocol { get }
    var togglePlayPauseCommand: RemoteCommandProtocol { get }
    var skipForwardCommand: RemoteCommandProtocol { get }
    var skipBackwardCommand: RemoteCommandProtocol { get }
    var nextTrackCommand: RemoteCommandProtocol { get }
    var previousTrackCommand: RemoteCommandProtocol { get }
    var seekForwardCommand: RemoteCommandProtocol { get }
    var seekBackwardCommand: RemoteCommandProtocol { get }
    var changePlaybackPositionCommand: RemoteCommandProtocol { get }
}

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
/// Make MPRemoteCommand conform to RemoteCommandProtocol
extension MPRemoteCommand: RemoteCommandProtocol { }

/// Wrapper to make MPRemoteCommandCenter conform to RemoteCommandCenterProtocol
public final class SystemRemoteCommandCenter: RemoteCommandCenterProtocol {
    private let commandCenter: MPRemoteCommandCenter

    public init(commandCenter: MPRemoteCommandCenter = .shared()) {
        self.commandCenter = commandCenter
    }
    
    public var playCommand: RemoteCommandProtocol { commandCenter.playCommand }
    public var pauseCommand: RemoteCommandProtocol { commandCenter.pauseCommand }
    public var stopCommand: RemoteCommandProtocol { commandCenter.stopCommand }
    public var togglePlayPauseCommand: RemoteCommandProtocol { commandCenter.togglePlayPauseCommand }
    public var skipForwardCommand: RemoteCommandProtocol { commandCenter.skipForwardCommand }
    public var skipBackwardCommand: RemoteCommandProtocol { commandCenter.skipBackwardCommand }
    public var nextTrackCommand: RemoteCommandProtocol { commandCenter.nextTrackCommand }
    public var previousTrackCommand: RemoteCommandProtocol { commandCenter.previousTrackCommand }
    public var seekForwardCommand: RemoteCommandProtocol { commandCenter.seekForwardCommand }
    public var seekBackwardCommand: RemoteCommandProtocol { commandCenter.seekBackwardCommand }
    public var changePlaybackPositionCommand: RemoteCommandProtocol { commandCenter.changePlaybackPositionCommand }
}
#endif

