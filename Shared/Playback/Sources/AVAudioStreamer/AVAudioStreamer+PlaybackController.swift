//
//  AVAudioStreamer+PlaybackController.swift
//  Playback
//
//  Extension to conform AVAudioStreamer to PlaybackController protocol
//

import Foundation
import AVFoundation
import PlaybackCore

#if os(iOS)
import UIKit
#endif

// AVAudioStreamer is not available on watchOS (AudioToolbox dependency)
#if !os(watchOS)

// MARK: - PlaybackController Conformance

extension AVAudioStreamer: PlaybackController {
    
    // streamURL is already defined in AVAudioStreamer
    
    public var isPlaying: Bool {
        streamingState == .playing
    }
    
    public var isLoading: Bool {
        switch streamingState {
        case .connecting, .buffering:
            return true
        default:
            return false
        }
    }
    
    public func play(reason: String) throws {
        Task {
            do {
                try await self.play()
            } catch {
                // Error is already handled by state change to .error
            }
        }
    }
    
    public func toggle(reason: String) throws {
        if isPlaying {
            pause()
        } else {
            try play(reason: reason)
        }
    }
    
    // audioBufferStream is defined in AVAudioStreamer class
    
    #if os(iOS)
    public func handleAppDidEnterBackground() {
        // If not playing, we don't need to do anything special
        // AVAudioStreamer uses AVAudioEngine which handles background audio automatically
        // when configured properly
        guard !isPlaying else { return }
        
        // Could deactivate audio session here if needed, but for streaming
        // we typically want to keep it active
    }
    
    public func handleAppWillEnterForeground() {
        // If we were playing, ensure playback continues
        // AVAudioEngine typically handles this automatically
    }
    #endif
}

#endif // !os(watchOS)
