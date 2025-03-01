//
//  PlaylistDataSource.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation
import Observation
import Core
import UIKit
import Logger

@Observable
final class PlaylistDataSource: Sendable {
    static let shared = PlaylistDataSource()

    init(playlistService: PlaylistService = .shared) {
        self.observePlaylist()
    }
    
    // MARK: Private
    
    private(set) var viewModels: [PlaylistCellViewModel] = []
    
    // I really didn't want to keep a local copy of the playlist here. However, I ran into problems with Swift's
    // `withObservationTracking` method where the playlist would fetch and update, but would consistently propagate
    // an empty playlist.
    private var playlist: Playlist = .empty

    private func observePlaylist() {
        let playlist = withObservationTracking {
            PlaylistService.shared.playlist
        } onChange: {
            self.observePlaylist()
        }
        
        self.updateViewModels(with: playlist)
    }
    
    private func updateViewModels(with playlist: Playlist) {
        guard playlist != self.playlist else {
            Log(.info,
                """
                No change in playlist: 
                old count \(self.playlist.entries.count)
                new count \(playlist.entries.count)
                """
            )
            
            return
        }
        self.playlist = playlist
        validateCollection(playlist.entries, label: "PlaylistDataSource Playlist")
        self.viewModels = playlist.entries
            .compactMap { $0 as? any PlaylistCellViewModelProducer }
            .map { $0.cellViewModel }
    }
}
