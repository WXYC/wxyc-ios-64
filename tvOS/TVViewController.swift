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

class TVViewController: UIViewController, NowPlayingPresentable, NowPlayingServiceObserver {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var songLabel: UILabel!
    
    var nowPlayingService: NowPlayingService?
    let radioPlayerController = RadioPlayerController()
    var radioPlayerStateObservation: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.albumImageView.layer.cornerRadius = 6.0
        self.albumImageView.layer.masksToBounds = true
        
        self.nowPlayingService = NowPlayingService(observers: self)
    }
}
