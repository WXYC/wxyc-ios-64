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

@MainActor
class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver, CPInterfaceControllerDelegate {
    var interfaceController: CPInterfaceController?
    var listTemplate: CPListTemplate?
    
    // MARK: CPTemplateApplicationSceneDelegate
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        PostHogSDK.shared.capture("carplay connected")
        
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
        let isPlaying = RadioPlayerController.shared.isPlaying
        let image = isPlaying
            ? nil
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
        PlaylistService.shared.observe { playlist in
            self.playlist = playlist
            self.updateListTemplate()
        }
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
