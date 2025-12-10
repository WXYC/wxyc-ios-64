//
//  RadioPlayerProtocols.swift
//  Core
//
//  Created for testability
//

import Foundation
import AVFoundation

// MARK: - Player Protocol

protocol PlayerProtocol: Sendable {
    var rate: Float { get }
    func play()
    func pause()
    func replaceCurrentItem(with item: AVPlayerItem?)
}

extension AVPlayer: PlayerProtocol {}
