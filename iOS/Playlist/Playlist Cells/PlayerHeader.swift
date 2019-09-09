//
//  PlaycutHeader.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/13/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import UIKit
import Core

@objc(PlayerHeader)
class PlayerHeader: UITableViewHeaderFooterView {
    @IBOutlet private var playButton: PlaybackButton!
    @IBOutlet private var cassetteContainer: UIView!
    @IBOutlet private var cassetteLeftReel: UIImageView!
    @IBOutlet private var cassetteRightReel: UIImageView!
    
    // MARK: Public
    
    override func prepareForReuse() {
        // Does science explain why simply overriding this method fixes a bug where the cassette
        // reels stop spinning if we scroll them off screen and back on again?
    }
    
    // MARK: Overrides
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.cassetteContainer.layer.cornerRadius = 6.0
        self.cassetteContainer.layer.masksToBounds = true
        
        self.setUpPlayback()
    }
    
    override class var requiresConstraintBasedLayout: Bool {
        return true
    }
    
    // MARK: Private
    
    private func setUpPlayback() {
        RadioPlayerController.shared.observePlaybackState(self.playbackStateChanged)
        self.playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
    }
    
    @objc private func playPauseTapped(_ sender: UIButton) {
        RadioPlayerController.shared.toggle()
    }
    
    private func playbackStateChanged(playbackState: PlaybackState) {
        switch playbackState {
        case .paused:
            self.cassetteLeftReel.stopSpin()
            self.cassetteRightReel.stopSpin()
            self.playButton.set(status: .paused, animated: self.shouldAnimateButtonTransition)
        case .playing:
            self.cassetteLeftReel.startSpin()
            self.cassetteRightReel.startSpin()
            self.playButton.set(status: .playing, animated: self.shouldAnimateButtonTransition)
        }
    }
    
    private var shouldAnimateButtonTransition: Bool {
        return UIApplication.shared.applicationState == .active
    }
}
