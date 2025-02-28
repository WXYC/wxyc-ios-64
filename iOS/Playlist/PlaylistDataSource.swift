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

@Observable
final class PlaylistDataSource: Sendable {
    static let shared = PlaylistDataSource()
    
    private(set) var viewModels: [PlaylistCellViewModel] = []

    @globalActor actor PlaylistDataSourceActor { static let shared = PlaylistDataSourceActor() }
    
    
    init(playlistService: PlaylistService = .shared) {
        self.observePlaylist()
    }
    
    private func observePlaylist() {
        let playlist = withObservationTracking {
            PlaylistService.shared.playlist
        } onChange: {
            Task { @MainActor in
                self.updateViewModels(with: PlaylistService.shared.playlist)
            }
            self.observePlaylist()
        }
        self.updateViewModels(with: playlist)
    }
    
    private func updateViewModels(with playlist: Playlist) {
        validateCollection(playlist.entries, label: "PlaylistDataSource Playlist")
        self.viewModels = playlist.entries
            .compactMap { $0 as? any PlaylistCellViewModelProducer }
            .map { $0.cellViewModel }
    }
}
