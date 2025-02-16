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
        
        DispatchQueue.main.async {
            self.cassetteContainer.layer.cornerRadius = 6.0
            self.cassetteContainer.layer.masksToBounds = true
            
            self.setUpPlayback()
        }
    }
    
    override class var requiresConstraintBasedLayout: Bool {
        return true
    }
    
    // MARK: Private
    
    private var playbackStateObservation: Any?
    private var notificationObservation: Any?
    
    private func setUpPlayback() {
        RadioPlayerController.shared.$isPlaying.observe(observer: self.playbackStateChanged(isPlaying:))
        self.playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        self.notificationObservation =
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification) { _ in
                DispatchQueue.main.async {
                    self.cassetteLeftReel.layer.removeAnimation(forKey: UIView.AnimationKey)
                    self.cassetteRightReel.layer.removeAnimation(forKey: UIView.AnimationKey)
                    self.playbackStateChanged(isPlaying: RadioPlayerController.shared.isPlaying)
                }
            }
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
        case .initialized:
            print("initialized")
            break

        }
    }
    
    private func playbackStateChanged(isPlaying: Bool) {
        switch isPlaying {
        case false:
            self.cassetteLeftReel.stopSpin()
            self.cassetteRightReel.stopSpin()
            self.playButton.set(status: .paused, animated: self.shouldAnimateButtonTransition)
        case true:
            self.cassetteLeftReel.startSpin()
            self.cassetteRightReel.startSpin()
            self.playButton.set(status: .playing, animated: self.shouldAnimateButtonTransition)
        }
    }
    
    private var shouldAnimateButtonTransition: Bool {
        return UIApplication.shared.applicationState == .active
    }
}

extension NotificationCenter {
    func addObserver(forName name: NSNotification.Name, using block: @escaping @Sendable (Notification) -> Void) -> any NSObjectProtocol {
        addObserver(forName: name, object: nil, queue: nil, using: block)
    }
}
