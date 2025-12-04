//
//  AudioPlayerController+PlaybackController.swift
//  WXYC
//
//  Extension to make AudioPlayerController conform to PlaybackController protocol.
//  This conformance allows AudioPlayerController to be used interchangeably with
//  RadioPlayerController via dependency injection.
//

import Foundation
import AVFoundation
import Core
import StreamingAudioPlayer

// MARK: - PlaybackController Conformance

extension AudioPlayerController: @preconcurrency PlaybackController {
    
    public var streamURL: URL {
        // Return the current URL or the default stream URL
        currentURL ?? defaultStreamURL ?? RadioStation.WXYC.streamURL
    }
    
    public func play(reason: String) throws {
        // AudioPlayerController uses the streamURL directly
        play(url: streamURL, reason: reason)
    }
    
    public func toggle(reason: String) throws {
        // AudioPlayerController's toggle doesn't take a reason,
        // but we match the protocol signature
        toggle()
    }
    
    // Explicit stop() to satisfy protocol (AudioPlayerController has stop(reason:))
    public func stop() {
        stop(reason: nil)
    }
    
    // Explicit pause() to satisfy protocol (AudioPlayerController has pause(reason:))  
    public func pause() {
        pause(reason: nil)
    }
}

