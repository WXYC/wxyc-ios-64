//
//  NowPlayingPresentable.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/2/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import Core

#if os(iOS)
public protocol NowPlayingPresentable: AnyObject, Sendable {
    var songLabel: UILabel! { get }
    var artistLabel: UILabel! { get }
    var albumImageView: UIImageView! { get }
    var userActivity: NSUserActivity? { get set }
}

@MainActor
public protocol NowPlayingObserver {
    func update(nowPlayingItem: NowPlayingItem?)
}

public extension NowPlayingPresentable where Self: NowPlayingObserver & Sendable {
    func update(nowPlayingItem: NowPlayingItem?) {
        self.update(playcut: nowPlayingItem?.playcut)
        self.update(artwork: nowPlayingItem?.artwork)
    }
    
    func update(playcut: Playcut?) {
        DispatchQueue.main.async {
            self.songLabel.text = playcut.songTitle
            self.artistLabel.text = playcut.artistName
            
            self.userActivity?.resignCurrent()
            self.userActivity = playcut.userActivity
            self.userActivity?.becomeCurrent()
        }
    }
    
    func update(artwork: UIImage?) {
        DispatchQueue.main.async {
            UIView.transition(
                with: self.albumImageView,
                duration: 0.25,
                options: [.transitionCrossDissolve],
                animations: { self.albumImageView.image = artwork.nowPlayingImage },
                completion: nil
            )
        }
    }
}

extension Optional where Wrapped == Playcut {
    var songTitle: String {
        switch self {
        case .some(let playcut):
            return playcut.songTitle
        case .none:
            return RadioStation.WXYC.name
        }
    }
    
    var artistName: String {
        switch self {
        case .some(let playcut):
            return playcut.artistName
        case .none:
            return RadioStation.WXYC.secondaryName
        }
    }
    
    var userActivity: NSUserActivity {
        switch self {
        case .some(let playcut):
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            let url: String! = "https://www.google.com/search?q=\(playcut.artistName)+\(playcut.songTitle)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            activity.webpageURL = URL(string: url)
            activity.title = "\(playcut.songTitle) by \(playcut.artistName)"
            
            return activity
        case .none:
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            activity.webpageURL = URL(string: "https://wxyc.org")!
            
            return activity
        }
    }
}

extension Optional where Wrapped == UIImage {
    var nowPlayingImage: UIImage {
        switch self {
        case .some(let image):
            return image
        case .none:
            return #imageLiteral(resourceName: "logo")
        }
    }
}
#endif
