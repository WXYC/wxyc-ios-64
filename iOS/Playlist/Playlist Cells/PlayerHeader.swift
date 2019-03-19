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
    
    private var radioPlayerStateObservation: Any?
    private var isPlaying = false
    
    required convenience init?(coder aDecoder: NSCoder) {
        self.init(reuseIdentifier: nil)
    }
    
    override required init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        guard let view = PlayerHeader.loadFromNib(owner: self) else {
            fatalError()
        }
        
        self.addSubview(view)
        self.addConstraints([
            self.topAnchor.constraint(equalTo: view.topAnchor),
            self.rightAnchor.constraint(equalTo: view.rightAnchor),
            self.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            self.leftAnchor.constraint(equalTo: view.leftAnchor),
        ])
        
        self.cassetteContainer.layer.cornerRadius = 6.0
        self.cassetteContainer.layer.masksToBounds = true
        
        self.setUpPlayback()
    }
    
    func setUpPlayback() {
        self.radioPlayerStateObservation = RadioPlayerController.shared.observePlaybackState(self.playbackStateChanged)
        self.playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
    }
    
    override class var requiresConstraintBasedLayout: Bool {
        return true
    }
    
    // MARK: Private
    
    @objc private func playPauseTapped(_ sender: UIButton) {
        switch self.isPlaying {
        case true:
            RadioPlayerController.shared.play()
        case false:
            RadioPlayerController.shared.pause()
        }
    }
    
    private func playbackStateChanged(playbackState: PlaybackState) {
        self.isPlaying.toggle()
        
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
