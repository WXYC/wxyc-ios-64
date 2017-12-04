//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit

protocol PlaylistServiceObserver {
    func updateWith(playcutResult: Result<Playcut>)
    func updateWith(artworkResult: Result<UIImage>)
}

final class PlaylistService {
    let webservice = Webservice()
    private var observers = [PlaylistServiceObserver]()
    
    init() {
        let playcutRequest = Future.repeat(webservice.getCurrentPlaycut)
        playcutRequest.observe(with: self.updateWith(playcutResult:))
        
        let imageRequest = playcutRequest.getArtwork()
        imageRequest.observe(with: self.update(artworkResult:))
    }
    
    func add(_ observers: PlaylistServiceObserver...) {
        for observer in observers {
            self.observers.append(observer)
        }
    }
    
    func updateWith(playcutResult: Result<Playcut>) {
        for observer in observers {
            observer.updateWith(playcutResult: playcutResult)
        }
    }
    
    func update(artworkResult: Result<UIImage>) {
        for observer in observers {
            observer.updateWith(artworkResult: artworkResult)
        }
    }
}

struct NowPlayingInfoService: PlaylistServiceObserver {
    let updateNowPlayingInfo: (NowPlayingInfo) -> ()
    let updateArtwork: (UIImage) -> ()
    
    func updateWith(playcutResult: Result<Playcut>) {
        switch playcutResult {
        case .success(let playcut):
            updateNowPlayingInfo(NowPlayingInfo(primaryHeading: playcut.songTitle, secondaryHeading: playcut.artistName))
        case .error(_):
            updateNowPlayingInfo(NowPlayingInfo.default)
        }
    }
    
    func updateWith(artworkResult: Result<UIImage>) {
        switch artworkResult {
        case .success(let image):
            updateArtwork(image)
        case .error(_):
            updateArtwork(#imageLiteral(resourceName: "logo"))
        }
    }
}
