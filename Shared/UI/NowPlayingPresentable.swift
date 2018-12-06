//
//  NowPlayingPresentable.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/2/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import Spring
import Core

public protocol NowPlayingPresentable: class {
    var songLabel: SpringLabel! { get }
    var artistLabel: UILabel! { get }
    var albumImageView: UIImageView! { get }
}

public extension PlaylistServiceObserver where Self: UIResponder & NowPlayingPresentable {
    func updateWith(playcutResult: Result<Playcut>) {
        DispatchQueue.main.async {
            switch playcutResult {
            case .success(let playcut):
                self.songLabel.text = playcut.songTitle
                self.artistLabel.text = playcut.artistName
                
                self.userActivity = playcut.userActivityState()
                self.userActivity?.becomeCurrent()
            case .error(_):
                self.songLabel.text = RadioStation.WXYC.name
                self.artistLabel.text = RadioStation.WXYC.secondaryName
            }
        }
    }
    
    func updateWith(artworkResult: Result<UIImage>) {
        DispatchQueue.main.async {
            UIView.transition(
                with: self.albumImageView,
                duration: 0.25,
                options: [.transitionCrossDissolve],
                animations: { self.albumImageView.image = artworkResult.nowPlayingImage },
                completion: nil
            )
        }
    }
}

extension Result where T == UIImage {
    var nowPlayingImage: UIImage {
        switch self {
        case .success(let image):
            return image
        case .error(_):
            return #imageLiteral(resourceName: "logo")
        }
    }
}
