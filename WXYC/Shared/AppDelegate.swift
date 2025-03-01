import Observation
@preconcurrency import CarPlay
import UIKit
import Core
import UI
import MediaPlayer
import WidgetKit
import Logger

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
        NowPlayingInfoCenterManager.shared.update(
            nowPlayingItem: NowPlayingService.shared.nowPlayingItem
        )
        WidgetCenter.shared.reloadAllTimelines()
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

// TODO: Move all this into a separate file.

class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver, CPInterfaceControllerDelegate {
    var interfaceController: CPInterfaceController?
    var listTemplate: CPListTemplate?
    
    // MARK: CPTemplateApplicationSceneDelegate
    
    nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        Task { @MainActor in
            self.interfaceController = interfaceController
            
            interfaceController.delegate = self
            self.setUpNowPlaying()
            
            let listTemplate = CPListTemplate(
                title: "WXYC 89.3 FM",
                sections: [self.makePlayerSection()]
            )
            self.listTemplate = listTemplate
            
            self.interfaceController?.setRootTemplate(listTemplate, animated: true) { success, error in
                Log(.info, "CPNowPlayingTemplate setRootTemplate: success: \(success), error: \(String(describing: error))")
                
                self.observeIsPlaying()
                self.observeNowPlaying()
                self.observePlaylist()
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
    
    private var playlist: Playlist = .empty
    
    nonisolated func main(_ work: @escaping @Sendable @MainActor () -> ()) {
        Task {
            await work()
        }
    }
    
    private func updateListTemplate() {
        guard let listTemplate else {
            return
        }
        
        listTemplate.updateSections([
            self.makePlayerSection(),
            self.makePlaylistSection()]
        )
    }
    
    
    private func makePlayerSection() -> CPListSection {
        let isPlaying = RadioPlayerController.shared.isPlaying
        let image = isPlaying
        ? UIImage(systemName: "pause.fill")
        : UIImage(systemName: "play.fill")
        let item = CPListItem(text: "Listen Live", detailText: nil, image: image)
        item.isPlaying = isPlaying
        
        item.handler = { selectableItem, completionHandler in
            RadioPlayerController.shared.play()
            self.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            completionHandler()
        }
        
        return CPListSection(items: [item])
    }
    
    private func makePlaylistSection() -> CPListSection {
        let playlistItems = playlist.entries.compactMap { entry in
            switch entry {
            case let entry as Playcut:
                CPListItem(playcut: entry)
            case _ as Talkset:
                CPListItem(text: nil, detailText: "Talkset", image: nil)
            case let entry as Breakpoint:
                CPListItem(text: nil, detailText: entry.formattedDate, image: nil)
            default:
                fatalError()
            }
        }
        
        return CPListSection(
            items: playlistItems,
            header: "Recently Played",
            sectionIndexTitle: nil
        )
    }
    
    func observeIsPlaying() {
        let _ = withObservationTracking {
            RadioPlayerController.shared.isPlaying
        } onChange: {
            Task { @MainActor in
                self.updateListTemplate()
                self.observeIsPlaying()
            }
        }
        
        self.updateListTemplate()
    }
    
    private func observeNowPlaying() {
        let nowPlayingItem = withObservationTracking {
            NowPlayingService.shared.nowPlayingItem
        } onChange: {
            Task { @MainActor in
                NowPlayingInfoCenterManager.shared.update(
                    nowPlayingItem: NowPlayingService.shared.nowPlayingItem
                )
                self.observeNowPlaying()
            }
        }
        
        NowPlayingInfoCenterManager.shared.update(nowPlayingItem: nowPlayingItem)
    }
    
    private func observePlaylist() {
        self.playlist = withObservationTracking {
            PlaylistService.shared.playlist
        } onChange: {
            Task { @MainActor in
                self.playlist = PlaylistService.shared.playlist
                self.updateListTemplate()
                self.observePlaylist()
            }
        }
        
        self.updateListTemplate()
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

extension CPListItem: @unchecked @retroactive Sendable {
    convenience init(playcut: Playcut) {
        self.init(text: playcut.artistName, detailText: playcut.songTitle)
        Task {
            let artwork = await ArtworkService.shared.getArtwork(for: playcut)
            
            Task { @MainActor in
                self.setImage(artwork)
            }
        }
    }
}
