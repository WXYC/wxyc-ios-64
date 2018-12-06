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
    var userActivity: NSUserActivity? { get set }
}

public extension NowPlayingPresentable where Self: PlaylistServiceObserver {
    func updateWith(playcutResult: Result<Playcut>) {
        DispatchQueue.main.async {
            self.songLabel.text = playcutResult.songTitle
            self.artistLabel.text = playcutResult.artistName
            
            self.userActivity = playcutResult.userActivity
            self.userActivity?.becomeCurrent()
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

extension Result where T == Playcut {
    var songTitle: String {
        switch self {
        case .success(let playcut):
            return playcut.songTitle
        case .error(_):
            return RadioStation.WXYC.name
        }
    }
    
    var artistName: String {
        switch self {
        case .success(let playcut):
            return playcut.artistName
        case .error(_):
            return RadioStation.WXYC.secondaryName
        }
    }
    
    var userActivity: NSUserActivity {
        switch self {
        case .success(let playcut):
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            let url: String! = "https://www.google.com/search?q=\(playcut.artistName)+\(playcut.songTitle)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            activity.webpageURL = URL(string: url)
            
            return activity
        case .error(_):
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            activity.webpageURL = URL(string: "https://wxyc.org")!
            
            return activity
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
