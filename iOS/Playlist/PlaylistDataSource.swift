//
//  PlaylistDataSource.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation
import Combine
import Core

final class PlaylistDataSource {
    typealias CellViewModel = PlaylistEntry & PlaylistCellViewModelProducer
    
    static let shared = PlaylistDataSource()
    
    @Published private(set) var viewModels: [PlaylistCellViewModel] = []
    
    init(playlistService: PlaylistService = .shared) {
        self.observation = playlistService.$playlist
            .map(\.entries.cellViewModels)
            .receive(on: RunLoop.main)
            .assign(to: \.viewModels, on: self)
    }
    
    private var observation: Cancellable? = nil
}

extension Sequence where Element == PlaylistEntry {
    var cellViewModels: [PlaylistCellViewModel] {
        return self
            .compactMap { $0 as? PlaylistCellViewModelProducer }
            .map { $0.cellViewModel }
    }
}
