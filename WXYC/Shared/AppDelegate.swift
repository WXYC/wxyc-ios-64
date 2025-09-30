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
        
        let playShortcut = UIApplicationShortcutItem(
            type: "org.wxyc.iphoneapp.play",
            localizedTitle: "Play WXYC",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .play),
            userInfo: [ "origin" : "home screen quick action" as NSString ]
        )
        application.shortcutItems = [playShortcut]
        
        return true
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard shortcutItem.type == "org.wxyc.iphoneapp.play" else {
            return false
        }

        do {
            try RadioPlayerController.shared.play(reason: "home screen play quick action")
            return true
        } catch {
            return false
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        PostHogSDK.shared.capture("Application Will Terminate", properties: [
            "Is Playing?" : RadioPlayerController.shared.isPlaying,
        ])
        UserDefaults.wxyc.set(false, forKey: "isPlaying")
        RadioPlayerController.shared.pause()
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
    static func donateSiriIntent() {
        let placeholder = UIImage.placeholder
        let mediaItem = INMediaItem(
            identifier: "Play WXYC",
            title: "Play WXYC",
            type: .radioStation,
            artwork: INImage(imageData: placeholder.pngData()!)
        )
        let intent = INPlayMediaIntent(
            mediaItems: [mediaItem],
            mediaContainer: nil,
            playShuffled: nil,
            resumePlayback: false,
            playbackQueueLocation: .now,
            playbackSpeed: nil
        )
        intent.suggestedInvocationPhrase = "Play \(RadioStation.WXYC.name)"
        let interaction = INInteraction(intent: intent, response: nil)
        
        Task {
            do {
                try await interaction.donate()
                
                let activity = NSUserActivity(activityType: "org.wxyc.iphoneapp.play")
                activity.title = "Play WXYC"
                activity.isEligibleForPrediction = true
                activity.isEligibleForSearch = true
                activity.suggestedInvocationPhrase = "Play WXYC"
                activity.userInfo = [ "origin" : "donateSiriIntent" ]
                activity.becomeCurrent()
                
                PostHogSDK.shared.capture(
                    "Intents",
                    context: "donateSiriIntent",
                    additionalData: [
                        "intent data" : activity.description
                    ]
                )
            } catch {
                Log(.error, "Failed to donate Siri intent: \(error)")
                PostHogSDK.shared.capture(error: error, context: "AppDelegate: Failed to donate Siri intent")
            }
        }
    }
    
    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        PostHogSDK.shared.capture(
            "Handle INIntent",
            context: "Intents",
            additionalData: [
                "intent data" : intent.description
            ])
        
        let response: INPlayMediaIntentResponse
        
        do {
            try RadioPlayerController.shared.play(reason: "INIntent")
            response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
            Log(.info, "Successfully handled INIntent: \(intent)")
        } catch {
            response = INPlayMediaIntentResponse(code: .failure, userActivity: nil)
            Log(.error, "Failed to handle INIntent: \(error)")
        }

        completionHandler(response)
    }
}
#endif

