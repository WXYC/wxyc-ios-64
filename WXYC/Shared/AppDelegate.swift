import Core
import Logger
import MediaPlayer
import Observation
import PostHog
import UI
import UIKit
import WidgetKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    let cacheCoordinator = CacheCoordinator.WXYCPlaylist
    
    // MARK: UIApplicationDelegate
    
    var window: UIWindow?
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        self.setUpAnalytics()
        PostHogSDK.shared.capture("app launch")
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            Log(.error, "Could not set AVAudioSession category: \(error)")
        }
        
#if os(iOS)
        // Make status bar white
        UINavigationBar.appearance().barStyle = .black
        // Siri intents are deprecated in favor of the App Intents framework. See Intents.swift.
        self.removeDonatedSiriIntentIfNeeded()
#endif
        
        observeNowPlayingItem()
        
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case let .success(configurations) = result else {
                return
            }
            
            for configuration in configurations {
                Log(.info, configuration)
            }
            
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
    
    // MARK: - Private
    
    // MARK: Now Playing Observation
    
    private var nowPlayingItem: Any?
    
    // TODO: Make a macro to encapsulate this.
    private func observeNowPlayingItem() {
        nowPlayingItem = withObservationTracking {
            NowPlayingService.shared.nowPlayingItem
        } onChange: {
            Task { @MainActor in
                self.updateNowPlayingInfo(NowPlayingService.shared.nowPlayingItem)
                self.observeNowPlayingItem()
            }
        }
    }
    
    func updateNowPlayingInfo(_ nowPlayingItem: NowPlayingItem?) {
        PostHogSDK.shared.capture("now playing updated")
        
        NowPlayingInfoCenterManager.shared.update(
            nowPlayingItem: NowPlayingService.shared.nowPlayingItem
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: PostHog Analytics
    
    func setUpAnalytics() {
        let POSTHOG_API_KEY = "phc_jUWlgO0aQzyPgHqQUEC7VPD1IdN1tytHG3qckb7CLoD"
        let POSTHOG_HOST = "https://us.i.posthog.com"

        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)
        
        PostHogSDK.shared.setup(config)
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

