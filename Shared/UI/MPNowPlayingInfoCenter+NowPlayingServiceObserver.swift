//
//  LockscreenInfoService.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import MediaPlayer
import Core

extension MPNowPlayingInfoCenter: NowPlayingObserver {
    public func update(nowPlayingItem: NowPlayingItem?) {
        Task.detached(priority: .userInitiated) {
            await self.update(playcut: nowPlayingItem?.playcut)
            await self.update(artwork: nowPlayingItem?.artwork)
        }
    }

    @MainActor func update(playcut: Playcut?) {
        if self.nowPlayingInfo == nil { self.nowPlayingInfo = [:] }
        
        self.nowPlayingInfo?.update(with: playcut.playcutMediaItems)
    }
    
    @MainActor func update(artwork: UIImage?) {
        if self.nowPlayingInfo == nil { self.nowPlayingInfo = [:] }
        
        self.nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork.mediaItemArtwork
    }
}

@MainActor extension Optional where Wrapped == UIImage {
    var mediaItemArtwork: MPMediaItemArtwork {
        let screenWidth = UIScreen.main.bounds.size.width
        let boundsSize = CGSize(width: screenWidth, height: screenWidth)
        
        return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            if case .some(let artwork) = self {
                return artwork
            } else {
                return UIImage.defaultNowPlayingInfoCenterImage
            }
        }
    }
}

extension Optional where Wrapped == Playcut {
    var playcutMediaItems: [String: Any] {
        if case .some(let playcut) = self {
            return [
                MPMediaItemPropertyArtist : playcut.artistName,
                MPMediaItemPropertyTitle: playcut.songTitle,
                MPMediaItemPropertyAlbumTitle: playcut.releaseTitle ?? ""
            ]
        } else {
            return [
                MPMediaItemPropertyArtist : RadioStation.WXYC.name,
                MPMediaItemPropertyTitle: RadioStation.WXYC.secondaryName,
                MPMediaItemPropertyAlbumTitle: ""
            ]
        }
    }
}

extension UIImage {
    @MainActor static var defaultNowPlayingInfoCenterImage: UIImage {
        let backgroundView = UIImageView(image: #imageLiteral(resourceName: "background"))
        let logoView = UIImageView(image: #imageLiteral(resourceName: "logo"))
        logoView.contentMode = .scaleAspectFit
        
        let width = UIScreen.main.bounds.width
        backgroundView.frame = CGRect(x: 0, y: 0, width: width, height: width)
        logoView.frame = backgroundView.frame
        
        backgroundView.addSubview(logoView)
        
        return backgroundView.snapshot()!
    }
}

extension Dictionary {
    mutating func update(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}
