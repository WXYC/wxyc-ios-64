//
//  NowPlayingService.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit

struct NowPlayingInfo {
    let primaryHeading: String
    let secondaryHeading: String
    
    static let `default` = NowPlayingInfo(
        primaryHeading: RadioStation.WXYC.name,
        secondaryHeading: RadioStation.WXYC.desc
    )
}

protocol NowPlayingServiceDelegate {
    func update(nowPlayingInfo: NowPlayingInfo)
    func update(artwork: UIImage)
}

final class NowPlayingService {
    private let delegate: NowPlayingServiceDelegate
    
    init(delegate: NowPlayingServiceDelegate) {
        self.delegate = delegate
        
        DispatchQueue.main.async {
            self.delegate.update(nowPlayingInfo: NowPlayingInfo.default)
        }
    }
    
    public func updateWith(playcutResult: Result<Playcut>) {
        switch playcutResult {
        case .success(let playcut):
            self.delegate.update(nowPlayingInfo: NowPlayingInfo(primaryHeading: playcut.songTitle, secondaryHeading: playcut.artistName))
        case .error(_):
            self.delegate.update(nowPlayingInfo: NowPlayingInfo.default)
        }
    }
    
    public func update(artworkResult: Result<UIImage>) {
        switch artworkResult {
        case .success(let image):
            self.delegate.update(artwork: image)
        case .error(_):
            self.delegate.update(artwork: #imageLiteral(resourceName: "logo"))
        }
    }
}
