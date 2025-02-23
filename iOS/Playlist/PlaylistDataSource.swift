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


final class PlaylistDataSource: Sendable {
    @Publishable private(set) var viewModels: [PlaylistCellViewModel] = []

    @globalActor actor PlaylistDataSourceActor { static let shared = PlaylistDataSourceActor() }
    
    static let shared = PlaylistDataSource()
    
    init(playlistService: PlaylistService = .shared) {
        playlistService.$playlist.observe { playlist in
            self.updateViewModels(with: playlist)
        }
    }
    
    private func updateViewModels(with playlist: Playlist) {
        self.viewModels = playlist.entries
            .compactMap { $0 as? any PlaylistCellViewModelProducer }
            .map { $0.cellViewModel }
    }
}
