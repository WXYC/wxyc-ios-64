//
//  NowPlayingPresentable.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/2/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit

protocol NowPlayingPresentable {
    weak var songLabel: SpringLabel! { get }
    weak var artistLabel: UILabel! { get }
    weak var albumImageView: UIImageView! { get }
}

extension NowPlayingServiceDelegate where Self: UIResponder & NowPlayingPresentable {
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
