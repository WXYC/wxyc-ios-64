import Core
import Foundation
import Intents
import Logger
import MediaPlayer
import Observation
import PostHog
import Secrets
import UIKit
import WidgetKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
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
            PostHogSDK.shared.capture(error: error, context: "AppDelegate: Could not set AVAudioSession category")
        }
        
        let _ = NowPlayingInfoCenterManager.shared
        
#if os(iOS)
        // Make status bar white
        UINavigationBar.appearance().barStyle = .black
        self.donateSiriIntent()
        #if false
        // Siri intents are deprecated in favor of the App Intents framework. See Intents.swift.
        self.removeDonatedSiriIntentIfNeeded()
        #endif
#endif
        
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case let .success(configurations) = result else {
                return
            }
            
            for configuration in configurations {
                Log(.info, configuration)
            }
            
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        // TODO: Figure out why this isn't working.
        #if false
        let playShortcut = UIApplicationShortcutItem(
            type: "org.wxyc.iphoneapp.play",
            localizedTitle: "Play WXYC",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .play),
            userInfo: nil
        )
        
        application.shortcutItems = [playShortcut]
        #endif
        
        return true
    }
    
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "org.wxyc.iphoneapp.play" {
            RadioPlayerController.shared.play()
            PostHogSDK.shared.capture("Play quick action")
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
    
    // MARK: - Private
    
    // MARK: PostHog Analytics
    
    private func setUpAnalytics() {
        let POSTHOG_API_KEY = Secrets.posthogApiKey
        let POSTHOG_HOST = "https://us.i.posthog.com"

        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)
        
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["Build Configuration" : self.buildConfiguration()])
    }
    
    private func buildConfiguration() -> String {
#if DEBUG
        return "Debug"
#elseif TEST_FLIGHT
        return "TestFlight"
#else
        return "Release"
#endif
    }
}

extension UIApplicationShortcutItem: @unchecked @retroactive Sendable { }

#if os(iOS)
import Intents

extension AppDelegate {
    private func donateSiriIntent() {
        let placeholder = UIImage.placeholder
        let mediaItem = INMediaItem(
            identifier: "Play WXYC",
            title: "Play WXYC",
            type: .radioStation,
            artwork: INImage(imageData: placeholder.pngData()!)
        )
        let intent = INPlayMediaIntent.init(mediaContainer: mediaItem)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                Log(.error, "Failed to donate Siri intent: \(error)")
                PostHogSDK.shared.capture(error: error, context: "AppDelegate: Failed to donate Siri intent")
            }
        }
        
        let activity = NSUserActivity(activityType: "org.wxyc.iphoneapp.play")
        activity.title = "Play WXYC"
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
        activity.suggestedInvocationPhrase = "Play WXYC"
        activity.becomeCurrent()
    }
    
    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        RadioPlayerController.shared.play()
        
        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        completionHandler(response)
    }
}
#endif

