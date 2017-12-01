//
//  RadioPlayer.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/1/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import AVFoundation

final class RadioPlayer {
    private let player = AVPlayer(url: URL.WXYCStream)
    
    public init() {
        // Notification for AVAudioSession Interruption (e.g. Phone call)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(RadioPlayer.sessionInterrupted),
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    deinit {
        // Be a good citizen
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    public var isPlaying: Bool {
        return player.isPlaying
    }
    
    public func play() {
        player.play()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEndTime(_:)),
            name: NSNotification.Name.AVPlayerItemPlaybackStalled,
            object: nil
        )
    }
    
    public func pause() {
        player.pause()
        self.resetStream()
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.AVPlayerItemPlaybackStalled,
            object: nil
        )
    }
    
    @objc private func playerItemFailedToPlayToEndTime(_ aNotification: Notification) {
        if kDebugLog {
            print("Network ERROR")
        }
        resetStream()
    }
    
    func resetStream() {
        let asset = AVAsset(url: URL.WXYCStream)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
    }
    
    // MARK: - AVAudio Sesssion Interrupted
    
    @objc func sessionInterrupted(notification: NSNotification) {
        if let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber{
            if let type = AVAudioSessionInterruptionType(rawValue: typeValue.uintValue) {
                if type == .began {
                    print("interruption: began")
                } else{
                    print("interruption: ended")
                    play()
                }
            }
        }
    }
}


private extension AVPlayer {
    var isPlaying: Bool {
        return rate > 0.0
    }
}
