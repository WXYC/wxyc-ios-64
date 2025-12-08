//
//  NowPlayingInfoCenterProtocol.swift
//  StreamingAudioPlayer
//
//  Protocol for now playing info center abstraction (wraps MPNowPlayingInfoCenter)
//

import Foundation
import MediaPlayer

/// Protocol defining the now playing info center interface for testability

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
/// Make MPNowPlayingInfoCenter conform to NowPlayingInfoCenterProtocol
extension MPNowPlayingInfoCenter {}
#endif
