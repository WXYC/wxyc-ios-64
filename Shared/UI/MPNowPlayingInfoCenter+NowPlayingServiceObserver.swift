//
//  LockscreenInfoService.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
@preconcurrency import MediaPlayer
import Core

extension MPNowPlayingInfoCenter: NowPlayingObserver {
    public func update(nowPlayingItem: NowPlayingItem?) {
        self.update(playcut: nowPlayingItem?.playcut)
        self.update(artwork: nowPlayingItem?.artwork)
    }

    func update(playcut: Playcut?) {
        let playcutMediaItems = playcut.playcutMediaItems
        Task { @MainActor in
            if self.nowPlayingInfo == nil { self.nowPlayingInfo = [:] }
            
            self.nowPlayingInfo?.update(with: playcutMediaItems)
        }
    }
    
    func update(artwork: UIImage?) {
        Task { @MainActor in
            if self.nowPlayingInfo == nil { self.nowPlayingInfo = [:] }
            
            self.nowPlayingInfo?[MPMediaItemPropertyArtwork] = await mediaItemArtwork(from: artwork)
        }
    }
    
    func mediaItemArtwork(from image: UIImage?) async -> MPMediaItemArtwork {
        let screenWidth = await UIScreen.main.bounds.size.width
        let boundsSize = CGSize(width: screenWidth, height: screenWidth)
        
        if let image {
            return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
                return image
            }
        } else {
            return await MPMediaItemArtwork.defaultArt()
        }
    }
}

extension MPMediaItemArtwork {
    @MainActor
    static func defaultArt() -> MPMediaItemArtwork {
        let backgroundView = UIImageView(image: #imageLiteral(resourceName: "background"))
        let logoView = UIImageView(image: #imageLiteral(resourceName: "logo"))
        logoView.contentMode = .scaleAspectFit
        
        let width = UIScreen.main.bounds.width
        backgroundView.frame = CGRect(x: 0, y: 0, width: width, height: width)
        logoView.frame = backgroundView.frame
        
        backgroundView.addSubview(logoView)
        
        return MPMediaItemArtwork(boundsSize: backgroundView.frame.size) { _ in
            backgroundView.snapshot()!
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

extension Dictionary {
    mutating func update(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}
