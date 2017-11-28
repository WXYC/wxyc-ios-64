//
//  LockscreenInfoService.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import MediaPlayer

final class LockscreenInfoService {
    private enum ServiceError: Error {
        case noPlaycut
        case noArtwork
    }
    
    private var playcutResult = Result<Playcut>.error(ServiceError.noPlaycut)
    private var artworkResult = Result<UIImage>.error(ServiceError.noArtwork)
    private var playbackRate: Float = 0.0
    
    public func updateWith(playcutResult: Result<Playcut>) {
        self.playcutResult = playcutResult
        self.updateNowPlayingInfoCenter()
    }
    
    public func update(artworkResult: Result<UIImage>) {
        self.artworkResult = artworkResult
        self.updateNowPlayingInfoCenter()
    }
    
    public func update(playbackRate: Float) {
        self.playbackRate = playbackRate
        self.updateNowPlayingInfoCenter()
    }
    
    private func mediaItemArtwork() -> MPMediaItemArtwork {
        let screenWidth = UIScreen.main.bounds.size.width
        let boundsSize = CGSize(width: screenWidth, height: screenWidth)
        
        return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            if case .success(let artwork) = self.artworkResult {
                return artwork
            } else {
                return UIImage.defaultNowPlayingInfoCenterImage
            }
        }
    }
    
    private func updateNowPlayingInfoCenter() {
        if case .success(let playcut) = playcutResult {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyArtist: playcut.artistName,
                MPMediaItemPropertyTitle: playcut.songTitle,
                MPMediaItemPropertyArtwork: self.mediaItemArtwork(),
                MPMediaItemPropertyAlbumTitle: playcut.releaseTitle ?? "",
                MPNowPlayingInfoPropertyIsLiveStream: self.playbackRate > 0.0,
                MPNowPlayingInfoPropertyPlaybackRate: self.playbackRate
            ]
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyArtist: RadioStation.WXYC.name,
                MPMediaItemPropertyTitle: RadioStation.WXYC.desc,
                MPMediaItemPropertyArtwork: UIImage.defaultNowPlayingInfoCenterImage,
                MPNowPlayingInfoPropertyIsLiveStream: self.playbackRate > 0.0,
                MPNowPlayingInfoPropertyPlaybackRate: self.playbackRate
            ]
        }
    }
}
