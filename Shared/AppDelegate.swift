import UIKit
import Combine
import Core
import UI
import MediaPlayer

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    let cacheCoordinator = CacheCoordinator.WXYCPlaylist
  
    var nowPlayingObservation: Any?
    var shouldDonateSiriIntentObservation: Cancellable?

    // MARK: UIApplicationDelegate
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
        #if os(iOS)
            // Make status bar white
            UINavigationBar.appearance().barStyle = .black
            self.donateSiriIntentIfNeeded()
        #endif
        
        self.nowPlayingObservation = NowPlayingService.shared.observe(with: MPNowPlayingInfoCenter.default())
        
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
    
    func donateSiriIntentIfNeeded() {
        Task {
            guard await self.shouldDonateSiriIntent() else {
                return
            }
            
            let mediaItem = INMediaItem(
                identifier: "com.wxyc.ios.intent.play",
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
            let interaction = INInteraction(intent: intent, response: nil)
            
            try await interaction.donate()
            await self.cacheCoordinator.set(value: true, for: UserSettingsKeys.intentDonated, lifespan: .distantFuture)
        }
    }

    func shouldDonateSiriIntent() async -> Bool {
        do {
            return try await self.cacheCoordinator.value(for: UserSettingsKeys.intentDonated)
        } catch {
            return false
        }
    }

    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        RadioPlayerController.shared.play()
        
        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        completionHandler(response)
    }
}

#endif
