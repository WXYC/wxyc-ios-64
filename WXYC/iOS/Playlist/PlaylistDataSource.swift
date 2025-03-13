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
import PostHog

@MainActor
@Observable
final class PlaylistDataSource: Sendable {
    static let shared = PlaylistDataSource()

    init(playlistService: PlaylistService = .shared) {
        PlaylistService.shared.observe { playlist in
            self.viewModels = playlist.entries
                .compactMap { $0 as? any PlaylistCellViewModelProducer }
                .map { $0.cellViewModel }
        }
    }
    
    // MARK: Private
    
    private(set) var viewModels: [PlaylistCellViewModel] = []
}
