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
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
        #if os(iOS)
            // Make status bar white
            UINavigationBar.appearance().barStyle = .black
            // Siri intents are deprecated in favor of the App Intents framework. See Intents.swift.
            self.removeDonatedSiriIntentIfNeeded()
        #endif
        
        self.nowPlayingObservation = NowPlayingService.shared.observe { nowPlayingItem in
            MPNowPlayingInfoCenter.default().update(nowPlayingItem: nowPlayingItem)
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case let .success(configurations) = result else {
                return
            }
            
            for configuration in configurations {
                print(configuration)
            }
            
            WidgetCenter.shared.reloadAllTimelines()
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
    
    func shouldRemoveSiriIntent() async throws -> Bool {
        try await !self.cacheCoordinator.value(for: UserSettingsKeys.intentDonated)
    }

    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        RadioPlayerController.shared.play()
        
        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        completionHandler(response)
    }
}

#endif

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        
    }
}