//
//  RadioPlayer+AudioPlayerProtocol.swift
//  PlaybackCore
//
//  Created by Jake Bromberg on 12/16/2025.
//  Copyright © 2025 wxyc.org. All rights reserved.
//
//  Extension to conform RadioPlayer to AudioPlayerProtocol
//

import Foundation
import AVFoundation
import PlaybackCore

// MARK: - AudioPlayerProtocol Conformance

extension RadioPlayer: AudioPlayerProtocol {

    // RadioPlayer now provides state, stateStream, audioBufferStream, and eventStream
    // as stored properties, so only the missing protocol methods need to be added here.

    public func stop() {
        pause()
    }

    /// No-op: AVPlayer-based RadioPlayer doesn't expose raw audio buffers
    public func installRenderTap() {
        // RadioPlayer uses AVPlayer which doesn't provide render tap access
    }

    /// No-op: AVPlayer-based RadioPlayer doesn't expose raw audio buffers
    public func removeRenderTap() {
        // RadioPlayer uses AVPlayer which doesn't provide render tap access
    }
}
