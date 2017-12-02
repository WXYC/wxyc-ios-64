//
//  ViewController.swift
//  WXYC TV
//
//  Created by Jake Bromberg on 12/2/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var songLabel: UILabel!
    
    let webservice = Webservice()
    lazy var nowPlayingService: NowPlayingService = {
        return NowPlayingService(delegate: self)
    }()
    let radioPlayer = RadioPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.albumImageView.layer.cornerRadius = 6.0
        self.albumImageView.layer.masksToBounds = true
        
        _ = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.checkPlaylist), userInfo: nil, repeats: true)
        
        self.checkPlaylist()
        self.radioPlayer.play()
    }

    @objc private func checkPlaylist() {
        let playcutRequest = webservice.getCurrentPlaycut()
        playcutRequest.observe(with: nowPlayingService.updateWith(playcutResult:))
        
        let imageRequest = playcutRequest.getArtwork()
        imageRequest.observe(with: nowPlayingService.update(artworkResult:))
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
    
    func playPressed() {
        radioPlayer.play()
    }
    
    func pausePressed() {
        radioPlayer.pause()
    }

}

extension ViewController: NowPlayingServiceDelegate {
    func update(nowPlayingInfo: NowPlayingInfo) {
        DispatchQueue.main.async {
            self.songLabel.text = nowPlayingInfo.primaryHeading
            self.artistLabel.text = nowPlayingInfo.secondaryHeading
        }
    }
    
    func update(artwork: UIImage) {
        DispatchQueue.main.async {
            UIView.transition(
                with: self.albumImageView,
                duration: 0.25,
                options: [.transitionCrossDissolve],
                animations: { self.albumImageView.image = artwork },
                completion: nil
            )
        }
    }
    
    func update(userActivityState: NSUserActivity) {
        DispatchQueue.main.async {
            self.userActivity = userActivityState
            self.userActivity?.becomeCurrent()
        }
    }
}
