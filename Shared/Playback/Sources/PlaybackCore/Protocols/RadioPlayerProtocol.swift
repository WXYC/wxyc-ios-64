//
//  RadioPlayerProtocol.swift
//  Playback
//
//  Created for testability
//
//  Created by Jake Bromberg on 11/11/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import AVFoundation

// MARK: - Player Protocol

public protocol PlayerProtocol: Sendable {
    var rate: Float { get }
    func play()
    func pause()
    func replaceCurrentItem(with item: AVPlayerItem?)
}

extension AVPlayer: PlayerProtocol {}
