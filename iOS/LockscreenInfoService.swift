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

final class LockscreenInfoService: NowPlayingServiceObserver {
    private var nowPlayingInfo = [String : Any]() {
        didSet {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
        }
    }
    
    public func updateWith(playcutResult: Result<Playcut>) {
        self.nowPlayingInfo.update(with: playcutResult.playcutMediaItems)
    }
    
    func updateWith(artworkResult: Result<UIImage>) {
        self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkResult.mediaItemArtwork
    }
}

extension Result where T == UIImage {
    var mediaItemArtwork: MPMediaItemArtwork {
        let screenWidth = UIScreen.main.bounds.size.width
        let boundsSize = CGSize(width: screenWidth, height: screenWidth)
        
        return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            if case .success(let artwork) = self {
                return artwork
            } else {
                return UIImage.defaultNowPlayingInfoCenterImage
            }
        }
    }
}

extension Result where T == Playcut {
    var playcutMediaItems: [String: Any] {
        if case .success(let playcut) = self {
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
    static var defaultNowPlayingInfoCenterImage: UIImage {
        let makeImage: () -> UIImage = {
            let backgroundView = UIImageView(image: #imageLiteral(resourceName: "background"))
            let logoView = UIImageView(image: #imageLiteral(resourceName: "logo"))
            logoView.contentMode = .scaleAspectFit
            
            let width = UIScreen.main.bounds.width
            backgroundView.frame = CGRect(x: 0, y: 0, width: width, height: width)
            logoView.frame = backgroundView.frame
            
            backgroundView.addSubview(logoView)
            
            return backgroundView.snapshot()!
        }
        
        if DispatchQueue.main == OperationQueue.current?.underlyingQueue {
            return makeImage()
        } else {
            return DispatchQueue.main.sync(execute: makeImage)
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
