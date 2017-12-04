//
//  ViewController.swift
//  WXYC TV
//
//  Created by Jake Bromberg on 12/2/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import MediaPlayer

class TVViewController: UIViewController, NowPlayingPresentable, PlaylistServiceObserver {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var songLabel: SpringLabel!
    
    var playlistService: PlaylistService?
    let radioPlayer = RadioPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.albumImageView.layer.cornerRadius = 6.0
        self.albumImageView.layer.masksToBounds = true
        
        self.setUpRemoteCommands()
        self.playlistService = PlaylistService(with: self)
        self.radioPlayer.play()
    }
    
    private func setUpRemoteCommands() {
        let playCommand = MPRemoteCommandCenter.shared().playCommand
        playCommand.isEnabled = true
        playCommand.addTarget(self, action: #selector(playPressed))
        
        let pauseCommand = MPRemoteCommandCenter.shared().pauseCommand
        pauseCommand.isEnabled = true
        pauseCommand.addTarget(self, action: #selector(pausePressed))
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .playPause:
                self.radioPlayer.isPlaying ? self.radioPlayer.pause() : self.radioPlayer.play()
            default:
                break
            }
        }
    }
    
    @objc private func playPressed() {
        radioPlayer.play()
    }
    
    @objc private func pausePressed() {
        radioPlayer.pause()
    }
}

