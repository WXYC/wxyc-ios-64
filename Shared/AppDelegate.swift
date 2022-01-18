import UIKit
import Combine
import Core
import UI
import MediaPlayer
import WidgetKit


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    let cacheCoordinator = CacheCoordinator.WXYCPlaylist
  
    var nowPlayingObservation: Any?
    var shouldDonateSiriIntentObservation: Cancellable?

    // MARK: UIApplicationDelegate
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.window = UIWindow()
        self.window?.makeKeyAndVisible()
        self.window?.rootViewController = RootPageViewController()
        
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        
        #if os(iOS)
            // Make status bar white
            UINavigationBar.appearance().barStyle = .black
            // Siri intents are deprecated in favor of the App Intents framework. See Intents.swift.
            self.removeDonatedSiriIntentIfNeeded()
        #endif
        
        self.nowPlayingObservation = NowPlayingService.shared.observe { nowPlayingItem in
            MPNowPlayingInfoCenter.default().update(nowPlayingItem: nowPlayingItem)
            WidgetCenter.shared.reloadAllTimelines()
            self.donate(nowPlayingItem: nowPlayingItem)
        }
        
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
}

#if os(iOS)
import Intents

extension AppDelegate {
    enum UserSettingsKeys: String {
        case intentDonated
    }
    
    func removeDonatedSiriIntentIfNeeded() {
        Task {
            guard try await self.shouldRemoveSiriIntent() else {
                return
            }
            
            try await INInteraction.deleteAll()
            await self.cacheCoordinator.set(
                value: nil as Bool?,
                for: UserSettingsKeys.intentDonated,
                lifespan: .distantFuture
            )
        }
    }
    
    func donate(nowPlayingItem: NowPlayingItem) {
        Task {
            let mediaItem = INMediaItem(nowPlayingItem)
            let intent = INSearchForMediaIntent(mediaItems: [mediaItem], mediaSearch: nil)
            intent.suggestedInvocationPhrase = "What's on WXYC?"
            
            let activity = NSUserActivity(nowPlayingItem)
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            
            let response = INSearchForMediaIntentResponse(code: .success, userActivity: activity)
            let interaction = INInteraction(intent: intent, response: response)
            do {
                try await interaction.donate()
            } catch {
                print(error)
            }
        }
    }

    func shouldRemoveSiriIntent() async throws -> Bool {
        try await !self.cacheCoordinator.value(for: UserSettingsKeys.intentDonated)
    }

    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        switch intent.identifier {
        case IntentIdentifiers.PlayWXYC:
            RadioPlayerController.shared.play()
            Task {
                let nowPlayingItem = await NowPlayingService.shared.fetch()
                let response = INPlayMediaIntentResponse(code: .success, userActivity: NSUserActivity(nowPlayingItem))
                response.nowPlayingInfo = [
                    MPMediaItemPropertyArtist : nowPlayingItem?.playcut.artistName as Any,
                    MPMediaItemPropertyTitle: nowPlayingItem?.playcut.songTitle as Any,
                    MPMediaItemPropertyAlbumTitle: nowPlayingItem?.playcut.releaseTitle as Any,
                ]
                completionHandler(response)
            }
        default:
            return
        }
    }
}

extension NSUserActivity {
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

enum IntentIdentifiers {
    static let PlayWXYC = "com.wxyc.ios.intent.play"
    static let WhatsPlayingOnWXYC = "com.wxyc.ios.intent.whatsPlayingOnWXYC"
}

extension INInteraction {
    
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
}

extension INMediaItem {
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

extension INImage {
    convenience init?(_ image: UIImage?) {
        if let artworkData = image?.pngData() {
            self.init(imageData: artworkData)
        } else {
            return nil
        }
    }
}

#endif

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        
    }
}