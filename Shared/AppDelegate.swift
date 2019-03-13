import UIKit
import AVFoundation
import Intents
import Core

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    let cacheCoordinator = CacheCoordinator.WXYCPlaylist
    var nowPlayingService: NowPlayingService?
    let lockscreenInfoService = LockscreenInfoService()

    enum UserSettingsKeys: String {
        case intentDonated
    }
    
    func donateSiriIntentIfNeeded() {
        self.shouldDonateSiriIntent().onSuccess { shouldDonateSiriIntent in
            guard shouldDonateSiriIntent else {
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
            
            interaction.donate()
            
            self.cacheCoordinator.set(value: true, for: UserSettingsKeys.intentDonated, lifespan: .distantFuture)
        }
    }
    
    func shouldDonateSiriIntent() -> Future<Bool> {
        return self.cacheCoordinator.getValue(for: UserSettingsKeys.intentDonated)
    }
    
    // MARK: UIApplicationDelegate
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
        #if os(iOS)
            // Make status bar white
            UINavigationBar.appearance().barStyle = .black
        #endif
        
        self.donateSiriIntentIfNeeded()
        
        self.nowPlayingService = NowPlayingService(observers: self.lockscreenInfoService)
        
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
    
    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        RadioPlayerController.shared.play()
        
        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        completionHandler(response)
    }
}
