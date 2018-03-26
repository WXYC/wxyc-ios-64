//
//  ViewController.swift
//  WXYC TV
//
//  Created by Jake Bromberg on 12/2/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import MediaPlayer
import Core
import UI
import Spring

class TVViewController: UIViewController, NowPlayingPresentable, PlaylistServiceObserver {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var songLabel: SpringLabel!
    
    var playlistService: PlaylistService?
    let radioPlayerController = RadioPlayerController()
    var radioPlayerStateObservation: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.albumImageView.layer.cornerRadius = 6.0
        self.albumImageView.layer.masksToBounds = true
        
        self.playlistService = PlaylistService(initialObservers: self)
    }
}
