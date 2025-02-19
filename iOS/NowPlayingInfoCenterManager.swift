//
//  NowPlayingInfoCenterManager.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/15/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import UI
import Foundation
import MediaPlayer

final class NowPlayingInfoCenterManager: NowPlayingObserver {
    public static let shared = NowPlayingInfoCenterManager()
    
    public func update(nowPlayingItem: NowPlayingItem?) {
        Task {
            await self.update(playcut: nowPlayingItem?.playcut)
            await self.update(artwork: nowPlayingItem?.artwork)
        }
    }

    @MainActor
    private func update(playcut: Playcut?) async {
        await MainActor.run { @MainActor in
            let playcutMediaItems = playcut.playcutMediaItems
            
            if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
            }
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo?.update(with: playcutMediaItems)
        }
    }

    @MainActor
    private func update(artwork: UIImage?) async {
        if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] =
            self.mediaItemArtwork(from: artwork)
    }
    
    @MainActor
    private func mediaItemArtwork(from image: UIImage?) -> MPMediaItemArtwork {
        if let image {
            let screenWidth = UIScreen.main.bounds.size.width
            let boundsSize = CGSize(width: screenWidth, height: screenWidth)
            
            return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
                return image
            }
        } else {
            return Self.defaultArt()
        }
    }
    
    @MainActor
    private static func defaultArt() -> MPMediaItemArtwork {
        var artwork: MPMediaItemArtwork!
        
        let backgroundView = UIImageView(image: #imageLiteral(resourceName: "background"))
        let logoView = UIImageView(image: #imageLiteral(resourceName: "logo"))
        logoView.contentMode = .scaleAspectFit
        
        let width = UIScreen.main.bounds.width
        backgroundView.frame = CGRect(x: 0, y: 0, width: width, height: width)
        logoView.frame = backgroundView.frame
        
        backgroundView.addSubview(logoView)
        
        artwork = MPMediaItemArtwork(boundsSize: backgroundView.frame.size) { _ in
            backgroundView.snapshot()!
        }
        
        return artwork
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
    @MainActor
    mutating func update(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}

