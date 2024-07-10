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

@Observable
@MainActor
final class PlaylistDataSource {
    static let shared = PlaylistDataSource()
    
    private(set) var viewModels: [PlaylistCellViewModel] = []
    
    init(playlistService: PlaylistService = .shared) {
        self.observation = withObservationTracking {
            playlistService.playlist
        } onChange: {
            Task { @MainActor in
                self.updateViewModels(with: playlistService.playlist.entries)
            }
        }
    }
    
    private var observation: Any? = nil
    
    private func updateViewModels(with entries: [any PlaylistEntry]) {
        self.viewModels = entries
            .compactMap { $0 as? any PlaylistCellViewModelProducer }
            .map { $0.cellViewModel }
    }
}
