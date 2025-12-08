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
final class SystemRemoteCommandCenter: RemoteCommandCenterProtocol {
    private let commandCenter: MPRemoteCommandCenter
    
    init(commandCenter: MPRemoteCommandCenter = .shared()) {
        self.commandCenter = commandCenter
    }
    
    var playCommand: RemoteCommandProtocol { commandCenter.playCommand }
    var pauseCommand: RemoteCommandProtocol { commandCenter.pauseCommand }
    var stopCommand: RemoteCommandProtocol { commandCenter.stopCommand }
    var togglePlayPauseCommand: RemoteCommandProtocol { commandCenter.togglePlayPauseCommand }
    var skipForwardCommand: RemoteCommandProtocol { commandCenter.skipForwardCommand }
    var skipBackwardCommand: RemoteCommandProtocol { commandCenter.skipBackwardCommand }
    var nextTrackCommand: RemoteCommandProtocol { commandCenter.nextTrackCommand }
    var previousTrackCommand: RemoteCommandProtocol { commandCenter.previousTrackCommand }
    var seekForwardCommand: RemoteCommandProtocol { commandCenter.seekForwardCommand }
    var seekBackwardCommand: RemoteCommandProtocol { commandCenter.seekBackwardCommand }
    var changePlaybackPositionCommand: RemoteCommandProtocol { commandCenter.changePlaybackPositionCommand }
}
#endif



