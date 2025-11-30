//
//  AudioSessionProtocol.swift
//  StreamingAudioPlayer
//
//  Protocol for audio session abstraction (wraps AVAudioSession)
//

import Foundation
import AVFoundation

#if os(iOS) || os(tvOS) || os(watchOS)

/// Protocol defining the audio session interface for testability
public protocol AudioSessionProtocol: AnyObject {
    /// Configure the audio session category
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    
    /// Activate or deactivate the audio session
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

/// Default implementation that wraps AVAudioSession.sharedInstance()
extension AVAudioSession: AudioSessionProtocol {
    // AVAudioSession already conforms to these methods
}

#else

/// Protocol defining the audio session interface for testability (macOS stub)
public protocol AudioSessionProtocol: AnyObject {
    /// Activate or deactivate the audio session
    func setActive(_ active: Bool) throws
}

#endif

/// A no-op audio session for platforms that don't support AVAudioSession or for testing
public final class NoOpAudioSession: AudioSessionProtocol {
    public init() {}
    
    #if os(iOS) || os(tvOS) || os(watchOS)
    public func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        // No-op
    }
    
    public func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        // No-op
    }
    #else
    public func setActive(_ active: Bool) throws {
        // No-op
    }
    #endif
}

