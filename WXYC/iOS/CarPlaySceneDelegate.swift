//
//  CarPlaySceneDelegate.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/1/25.
//

import Foundation
@preconcurrency import CarPlay
import Logger
import Core
import PostHog
import Intents
import SwiftUI

@MainActor
class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver, CPInterfaceControllerDelegate {
    var interfaceController: CPInterfaceController?
    var listTemplate: CPListTemplate?
    let playlistService = PlaylistService()

    private var radioPlayerController: RadioPlayerController {
        AppState.shared.radioPlayerController
    }
    
    // MARK: CPTemplateApplicationSceneDelegate
    
    nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        PostHogSDK.shared.capture("carplay connected")
        
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
                
                Task { @MainActor in
                    self.observeIsPlaying()
                    self.observePlaylist()
                }
            }
        }
    }
    
    nonisolated func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
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
        let isPlaying = radioPlayerController.isPlaying
        let image = isPlaying
            ? nil
            : UIImage(systemName: "play.fill")
        let listenLiveItem = CPListItem(text: "Listen Live", detailText: nil, image: image)
        listenLiveItem.isPlaying = isPlaying

        listenLiveItem.handler = { selectableItem, completionHandler in
            try? self.radioPlayerController.play(reason: "CarPlay listen live tapped")
            
            self.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { success, error in
                if let error {
                    Log(.error, "Could not push now playing template: \(error)")
                    PostHogSDK.shared.capture(error: error, context: "CarPlay: Could not push now playing template")
                }
            }
            completionHandler()
        }
        
        return CPListSection(items: [listenLiveItem])
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
        
        playlistItems.forEach {
            $0.handler = { item, completion in
                completion()
                item.isEnabled = false
                item.isEnabled = true
            }
        }
        
        return CPListSection(
            items: playlistItems,
            header: "Recently Played",
            sectionIndexTitle: nil
        )
    }
    
    @MainActor
    private func observeIsPlaying() {
        let observations = Observations {
            self.radioPlayerController.isPlaying
        }

        Task {
            for await _ in observations {
                self.updateListTemplate()
            }
        }
    }
    
    @MainActor
    private func observePlaylist() {
        Task {
            for await playlist in playlistService {
                self.playlist = playlist
                self.updateListTemplate()
            }
        }
    }
}

class LoggerWindowSceneDelegate: NSObject, UIWindowSceneDelegate {

    internal var window: UIWindow?

    private var radioPlayerController: RadioPlayerController {
        AppState.shared.radioPlayerController
    }
    
    // MARK: UISceneDelegate
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let ua = connectionOptions.userActivities.first {
            try? handle(userActivity: ua)
        }

        guard let windowScene = scene as? UIWindowScene,
              session.configuration.name == "LoggerSceneConfiguration" else {
            return
        }
        
        window = UIWindow(frame: windowScene.coordinateSpace.bounds)

        window?.rootViewController = UIHostingController(rootView: RootTabView())
        window?.windowScene = windowScene
        window?.makeKeyAndVisible()
    }
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard shortcutItem.type == "org.wxyc.iphoneapp.play" else {
            return false
        }

        do {
            try radioPlayerController.play(reason: "home screen play quick action")
            return true
        } catch {
            return false
        }
    }
    
    private func handle(userActivity: NSUserActivity) throws {
        if userActivity.activityType == "org.wxyc.iphoneapp.play" {
            try radioPlayerController.play(reason: "Siri suggestion (NSUserActivity)")
        } else if let _ = userActivity.interaction?.intent as? INPlayMediaIntent {
            try radioPlayerController.play(reason: "Siri suggestion (INPlayMediaIntent)")
        }
    }
}

extension CPListItem: @unchecked @retroactive Sendable {
    convenience init(playcut: Playcut) {
        self.init(text: playcut.artistName, detailText: playcut.songTitle)
        Task {
            let artworkService = MultisourceArtworkService()
            let artwork = try await artworkService.fetchArtwork(for: playcut)

            Task { @MainActor in
                self.setImage(artwork)
            }
        }
    }
}
