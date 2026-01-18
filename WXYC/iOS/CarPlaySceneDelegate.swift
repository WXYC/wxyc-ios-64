//
//  CarPlaySceneDelegate.swift
//  WXYC
//
//  Scene delegate for CarPlay interface.
//
//  Created by dvd on 09/27/17.
//  Copyright © 2017 WXYC. All rights reserved.
//

import Foundation
@preconcurrency import CarPlay
import Core
import Logger
import PostHog
import Intents
import SwiftUI
import PlayerHeaderView
import Playback
import Playlist
import Artwork

@MainActor
class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver, CPInterfaceControllerDelegate {
    var interfaceController: CPInterfaceController?
    var listTemplate: CPListTemplate?
    var playlistService: PlaylistService { Singletonia.shared.playlistService }
    
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
                Log(.info, category: .ui, "CPNowPlayingTemplate setRootTemplate: success: \(success), error: \(String(describing: error))")
                
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
        Log(.info, category: .ui, "Hello, World!")
    }
    
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Log(.info, category: .ui, "Hello, World!")
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
        let isPlaying = AudioPlayerController.shared.isPlaying
        let image = isPlaying
            ? nil
            : UIImage(systemName: "play.fill")
        let listenLiveItem = CPListItem(text: "Listen Live", detailText: nil, image: image)
        listenLiveItem.isPlaying = isPlaying

        listenLiveItem.handler = { (_: CPSelectableListItem, completionHandler: @escaping () -> Void) in
            AudioPlayerController.shared.play()
            
            self.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { success, error in
                if let error {
                    Log(.error, category: .ui, "Could not push now playing template: \(error)")
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
            $0.handler = { (item: CPSelectableListItem, completion: @escaping () -> Void) in
                completion()
                // Briefly disable/enable to give selection feedback if it’s a CPListItem
                if let listItem = item as? CPListItem {
                    listItem.isEnabled = false
                    listItem.isEnabled = true
                }
            }
        }
        
        return CPListSection(
            items: playlistItems,
            header: "Recently Played",
            sectionIndexTitle: nil
        )
    }
    
    private nonisolated func observeIsPlaying() {
        Task { @MainActor in
            let observation = Observations {
                AudioPlayerController.shared.isPlaying
            }
            
            for await _ in observation {
                self.updateListTemplate()
            }
        }
    }
    
    @MainActor
    private func observePlaylist() {
        Task {
            for await playlist in playlistService.updates() {
                self.playlist = playlist
                self.updateListTemplate()
            }
        }
    }
}

extension CPListItem: @unchecked @retroactive Sendable {
    convenience init(playcut: Playcut) {
        self.init(text: playcut.artistName, detailText: playcut.songTitle)
        Task {
            let artworkService = MultisourceArtworkService()
            let cgImage = try await artworkService.fetchArtwork(for: playcut)

            Task { @MainActor in
                self.setImage(cgImage.toUIImage())
            }
        }
    }
}
