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
        secondaryHeading: RadioStation.WXYC.secondaryName
    )
}

protocol NowPlayingServiceDelegate {
    func update(nowPlayingInfo: NowPlayingInfo)
    func update(artwork: UIImage)
    func update(userActivityState: NSUserActivity)
}

final class NowPlayingService {
    private let webservice = Webservice()
    private let delegate: NowPlayingServiceDelegate
    
    init(delegate: NowPlayingServiceDelegate) {
        self.delegate = delegate
        
        DispatchQueue.main.async {
            self.delegate.update(nowPlayingInfo: NowPlayingInfo.default)
        }
    }
    
    public func start() {
        _ = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.checkPlaylist), userInfo: nil, repeats: true)
        
        self.checkPlaylist()
    }
    
    @objc private func checkPlaylist() {
        let playcutRequest = webservice.getCurrentPlaycut()
        playcutRequest.observe(with: self.updateWith(playcutResult:))
        
        let imageRequest = playcutRequest.getArtwork()
        imageRequest.observe(with: self.update(artworkResult:))
    }
    
    public func updateWith(playcutResult: Result<Playcut>) {
        switch playcutResult {
        case .success(let playcut):
            self.delegate.update(nowPlayingInfo: NowPlayingInfo(primaryHeading: playcut.songTitle, secondaryHeading: playcut.artistName))
            self.delegate.update(userActivityState: playcut.userActivityState())
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

extension Playcut {
    func userActivityState() -> NSUserActivity {
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        let url: String! = "https://www.google.com/search?q=\(artistName)+\(songTitle)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        activity.webpageURL = URL(string: url)
        
        return activity
    }
}
