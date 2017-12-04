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

final class NowPlayingService: PlaylistServiceObserver {
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
            self.delegate.update(userActivityState: playcut.userActivityState())
        case .error(_):
            self.delegate.update(nowPlayingInfo: NowPlayingInfo.default)
        }
    }
    
    public func updateWith(artworkResult: Result<UIImage>) {
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

extension Future {
    static func `repeat`(_ future: @escaping () -> (Future), timeInterval: TimeInterval = 30) -> Future {
        let promise = Promise<Value>()
        
        let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
            future().observe(with: { result in
                switch result {
                case .success(let success):
                    promise.resolve(with: success)
                case .error(let error):
                    promise.reject(with: error)
                }
            })
        }
        
        timer.fire()
        
        return promise
    }
}

