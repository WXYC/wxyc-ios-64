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

final class PlaylistDataSource: Sendable {
    @Publishable private(set) var viewModels: [PlaylistCellViewModel] = []

    static let shared = PlaylistDataSource()
    
    init(playlistService: PlaylistService = .shared) {
        playlistService.$playlist.observe(observer: self.updateViewModels(with: ))
    }
    
    private var playlistServiceObserver: Any? = nil
    
    private func updateViewModels(with entries: [any PlaylistEntry]) {
        self.viewModels = entries
            .compactMap { $0 as? any PlaylistCellViewModelProducer }
            .map { $0.cellViewModel }
    }
    
    private func updateViewModels(with playlist: Playlist) {
        self.viewModels = playlist.entries
            .compactMap { $0 as? any PlaylistCellViewModelProducer }
            .map { $0.cellViewModel }
    }
}
