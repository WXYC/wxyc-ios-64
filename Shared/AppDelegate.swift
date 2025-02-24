import Observation
import CarPlay
import UIKit
import Core
import UI
import MediaPlayer
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

        Task {
            await NowPlayingService.shared.$nowPlayingItem.observe { @MainActor nowPlayingItem in
                NowPlayingInfoCenterManager.shared.update(nowPlayingItem: nowPlayingItem)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        
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

class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver, CPInterfaceControllerDelegate {
    var interfaceController: CPInterfaceController?
    
    var observer: Any?
    
    nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        main { @MainActor in
            self.interfaceController = interfaceController
            
            interfaceController.delegate = self
            self.setUpNowPlaying()

            let item = self.makeListItem()
            let section = CPListSection(items: [item])
            let listTemplate = CPListTemplate(title: "WXYC 89.3 FM", sections: [section])
            
            self.interfaceController?.setRootTemplate(listTemplate, animated: true) { success, error in
                Log(.info, "CPNowPlayingTemplate setRootTemplate: success: \(success), error: \(String(describing: error))")
                
                Task {
                    await NowPlayingService.shared.$nowPlayingItem.observe { @MainActor nowPlayingItem in
                        NowPlayingInfoCenterManager.shared.update(nowPlayingItem: nowPlayingItem)
                    }
                }
            }
        }
    }
    
    nonisolated func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        main {
            self.interfaceController = nil
            templateApplicationScene.delegate = self
            
            CPNowPlayingTemplate.shared.remove(self)
        }
    }
    
    nonisolated func main(_ work: @escaping @Sendable @MainActor () -> ()) {
        Task {
            await work()
        }
    }
    
    // MARK: CPNowPlayingTemplateObserver
    
    private func setUpNowPlaying() {
        CPNowPlayingTemplate.shared.isUpNextButtonEnabled = false
        CPNowPlayingTemplate.shared.isAlbumArtistButtonEnabled = false
        CPNowPlayingTemplate.shared.add(self)
    }
    
    nonisolated func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Log(.info, "Hello, World!")
    }
    
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Log(.info, "Hello, World!")
    }
    
    // MARK: Private
    
    private func makeListItem() -> CPListItem {
        let nowPlayingItem = NowPlayingService.shared.nowPlayingItem
        
        let artist = nowPlayingItem?.playcut.artistName
        let song = nowPlayingItem?.playcut.songTitle
        let detailedText: String? =
            artist == nil && song == nil
                ? nil
                : "\(artist!) • \(song!)"
        
        let defaultArtwork = UIImage(imageLiteralResourceName: "logo.pdf")
            .withTintColor(.systemPurple, renderingMode: .alwaysTemplate)

        let mediaItemArtwork = nowPlayingItem?.artwork ?? defaultArtwork        
        let item = CPListItem(text: "Listen Live", detailText: detailedText, image: mediaItemArtwork)
        item.handler = { selectableItem, completionHandler in
            RadioPlayerController.shared.play()
            self.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            completionHandler()
        }
        return item
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

extension CPInterfaceController: @unchecked @retroactive Sendable {
    
}
