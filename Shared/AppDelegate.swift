import UIKit
import Combine
import Core
import Intents
import UI
import MediaPlayer
import WidgetKit

@UIApplicationMain
@MainActor
class AppDelegate: UIResponder, UIApplicationDelegate {
    let cacheCoordinator = CacheCoordinator.WXYCPlaylist
    var nowPlayingObservation: Any?

    // MARK: UIApplicationDelegate
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.window = UIWindow()
        self.window?.makeKeyAndVisible()
        self.window?.rootViewController = RootPageViewController()
        
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        // Make status bar white
        UINavigationBar.appearance().barStyle = .black

        Task {
#if os(iOS)
            await SiriService.shared.donateSiriIntentIfNeeded()
#endif
            
            self.nowPlayingObservation = NowPlayingService.shared.observe { nowPlayingItem in
                MPNowPlayingInfoCenter.default().update(nowPlayingItem: nowPlayingItem)
                WidgetCenter.shared.reloadAllTimelines()
                Task { await SiriService.shared.donate(nowPlayingItem: nowPlayingItem) }
            }
        }
        
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
    
#if os(iOS)
    func application(_ application: UIApplication, handle intent: INIntent) async -> INIntentResponse {
        return await SiriService.shared.handle(intent: intent)
    }
#endif
}
