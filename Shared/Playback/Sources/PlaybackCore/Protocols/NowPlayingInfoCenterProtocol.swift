//
//  NowPlayingInfoCenterProtocol.swift
//  Playback
//
//  Protocol for now playing info center abstraction (wraps MPNowPlayingInfoCenter)
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import MediaPlayer

/// Protocol defining the now playing info center interface for testability

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
/// Make MPNowPlayingInfoCenter conform to NowPlayingInfoCenterProtocol
extension MPNowPlayingInfoCenter {}
#endif
