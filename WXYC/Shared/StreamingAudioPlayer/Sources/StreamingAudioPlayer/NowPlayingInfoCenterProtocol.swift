//
//  NowPlayingInfoCenterProtocol.swift
//  StreamingAudioPlayer
//
//  Protocol for now playing info center abstraction (wraps MPNowPlayingInfoCenter)
//

import Foundation
import MediaPlayer

/// Protocol defining the now playing info center interface for testability
public protocol NowPlayingInfoCenterProtocol: AnyObject {
    /// The current now playing info dictionary
    var nowPlayingInfo: [String: Any]? { get set }
    
    /// The current playback state
    var playbackState: MPNowPlayingPlaybackState { get set }
}

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
/// Make MPNowPlayingInfoCenter conform to NowPlayingInfoCenterProtocol
extension MPNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {}
#endif



