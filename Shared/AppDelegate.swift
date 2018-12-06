import UIKit
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
        #if os(iOS)
            // Make status bar white
            UINavigationBar.appearance().barStyle = .black
        #endif
        
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
}
