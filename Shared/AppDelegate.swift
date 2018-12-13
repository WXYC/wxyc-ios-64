import UIKit
import AVFoundation
import Intents
import Core

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    enum UserSettingsKeys: String {
        case intentDonated
    }
    
    func donateSiriIntentIfNeeded() {
        guard self.shouldDonateSiriIntent() else {
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
        
        UserDefaults.standard[UserSettingsKeys.intentDonated] = true
    }
    
    func shouldDonateSiriIntent() -> Bool {
        return UserDefaults.standard[UserSettingsKeys.intentDonated] == true
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
