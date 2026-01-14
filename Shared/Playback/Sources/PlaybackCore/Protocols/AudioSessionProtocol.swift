//
//  AudioSessionProtocol.swift
//  Playback
//
//  Protocol for audio session abstraction (wraps AVAudioSession)
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
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

    /// The current audio route
    var currentRoute: AVAudioSessionRouteDescription { get }
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
