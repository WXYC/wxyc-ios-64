//
//  SiriSerevice.swift
//  Core
//
//  Created by Jake Bromberg on 6/12/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import Foundation
import Intents
import MediaPlayer

public actor SiriService {
    enum Error: Swift.Error {
        case unknownIntentIdentifier
    }
    
    public static let shared = SiriService()
    
    init(cacheCoordinator: CacheCoordinator = .WXYCPlaylist) {
        self.cacheCoordinator = cacheCoordinator
    }
    
#if os(iOS)
    public func handle(intent: INIntent) async -> INIntentResponse {
        switch intent.identifier {
        case IntentIdentifiers.PlayWXYC:
            RadioPlayerController.shared.play()
            let nowPlayingItem = await NowPlayingService.shared.fetch()
            return INPlayMediaIntentResponse(nowPlayingItem: nowPlayingItem)
        default:
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }
    }
#endif
    
    // MARK: Private
    
    private let cacheCoordinator: CacheCoordinator
}

enum IntentIdentifiers {
    static let PlayWXYC = "com.wxyc.ios.intent.play"
    static let WhatsPlayingOnWXYC = "com.wxyc.ios.intent.whatsPlayingOnWXYC"
}

extension SiriService {
    enum UserSettingsKeys: String {
        case intentDonated
    }
    
    public func donateSiriIntentIfNeeded() async {
        guard await self.shouldDonateSiriIntent() else {
            return
        }

        do {
            try await INInteraction.playWXYC.donate()
            await self.cacheCoordinator.set(value: true, for: UserSettingsKeys.intentDonated, lifespan: .distantFuture)
        } catch {
            print("Could not donate Siri intent: \(error)")
        }
    }
    
    public func donate(nowPlayingItem: NowPlayingItem) async {
        do {
            try await INInteraction.whatsOnWXYC(with: nowPlayingItem).donate()
        } catch {
            print(error)
        }
    }

    func shouldDonateSiriIntent() async -> Bool {
        do {
            return try await self.cacheCoordinator.value(for: UserSettingsKeys.intentDonated)
        } catch {
            return false
        }
    }
}

private extension INPlayMediaIntentResponse {
    convenience init(nowPlayingItem: NowPlayingItem?) {
        self.init(code: .success, userActivity: NSUserActivity(nowPlayingItem))
        self.nowPlayingInfo = [
            MPMediaItemPropertyArtist : nowPlayingItem?.playcut.artistName as Any,
            MPMediaItemPropertyTitle: nowPlayingItem?.playcut.songTitle as Any,
            MPMediaItemPropertyAlbumTitle: nowPlayingItem?.playcut.releaseTitle as Any,
        ]
    }
}

private extension NSUserActivity {
    convenience init(_ nowPlayingItem: NowPlayingItem?) {
        switch nowPlayingItem {
        case .some(let nowPlayingItem):
            self.init(activityType: NSUserActivityTypeBrowsingWeb)
            let url: String! = "https://www.google.com/search?q=\(nowPlayingItem.playcut.artistName)+\(nowPlayingItem.playcut.songTitle)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            self.webpageURL = URL(string: url)
        case .none:
            self.init(activityType: NSUserActivityTypeBrowsingWeb)
            self.webpageURL = URL(string: "https://wxyc.org")!
        }
    }
}

private extension INInteraction {
    
    static var playWXYC: Self {
        let mediaItem = INMediaItem(
            identifier: IntentIdentifiers.PlayWXYC,
            title: "Play",
            type: .musicStation,
            artwork: nil
        )
        
        let intent = INPlayMediaIntent(
            mediaItems: [mediaItem],
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: false
        )
        
        intent.suggestedInvocationPhrase = "Play WXYC"
        return Self(intent: intent, response: nil)
    }
    
    static func whatsOnWXYC(with nowPlayingItem: NowPlayingItem) -> Self {
        let mediaItem = INMediaItem(nowPlayingItem)
        let intent = INSearchForMediaIntent(mediaItems: [mediaItem], mediaSearch: nil)
        intent.suggestedInvocationPhrase = "What's on WXYC?"
        
        let activity = NSUserActivity(nowPlayingItem)
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        
        let response = INSearchForMediaIntentResponse(code: .success, userActivity: activity)
        return Self(intent: intent, response: response)
    }
}

private extension INMediaItem {
    convenience init(_ nowPlayingItem: NowPlayingItem) {
        self.init(
            identifier: IntentIdentifiers.WhatsPlayingOnWXYC,
            title: nowPlayingItem.playcut.songTitle,
            type: .song,
            artwork: INImage(nowPlayingItem.artwork),
            artist: nowPlayingItem.playcut.artistName
        )
    }
}

private extension INImage {
    convenience init?(_ image: UIImage?) {
        if let artworkData = image?.pngData() {
            self.init(imageData: artworkData)
        } else {
            return nil
        }
    }
}
