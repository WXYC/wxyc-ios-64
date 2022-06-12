import UIKit
import Combine
import Core
import Intents
import UI
import MediaPlayer
import WidgetKit
import CarPlay
import SwiftUI


@UIApplicationMain
@MainActor
class AppDelegate: UIResponder, UIApplicationDelegate {
    let cacheCoordinator = CacheCoordinator.WXYCPlaylist
    var nowPlayingObservation: Any?
    
    // MARK: UIApplicationDelegate
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        
        if nowPlayingInfoCenter.nowPlayingInfo == nil {
            nowPlayingInfoCenter.nowPlayingInfo = [:]
        }
        
        nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyIsLiveStream] = true
        
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
#if os(iOS)
        // Make status bar white
        UINavigationBar.appearance().barStyle = .black
        Task { await SiriService.shared.donateSiriIntentIfNeeded() }
#endif
        
        self.nowPlayingObservation = NowPlayingService.shared.observe { nowPlayingItem in
            nowPlayingInfoCenter.update(nowPlayingItem: nowPlayingItem)
            WidgetCenter.shared.reloadAllTimelines()
            Task { await SiriService.shared.donate(nowPlayingItem: nowPlayingItem)}
            CPNowPlayingTemplate.shared.userInfo = nowPlayingItem.toUserInfo()
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

extension AppDelegate: CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
    static var interfaceController: CPInterfaceController?
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        Self.interfaceController = interfaceController
        
        Self.interfaceController?.setRootTemplate(CPNowPlayingTemplate.shared, animated: true) { success, error in
            print("success: \(success), error: \(error)")
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        Self.interfaceController = nil
    }
}

class LoggerWindowSceneDelegate: NSObject, UIWindowSceneDelegate {
    
    internal var window: UIWindow?
    
    // MARK: UISceneDelegate
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene, session.configuration.name == "LoggerSceneConfiguration" else { return }
        
        window = UIWindow(frame: windowScene.coordinateSpace.bounds)
        
        window?.rootViewController = RootPageViewController()
        window?.windowScene = windowScene
        window?.makeKeyAndVisible()
    }
}
