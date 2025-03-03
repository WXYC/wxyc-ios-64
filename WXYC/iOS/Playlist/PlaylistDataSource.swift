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
    
    private func observePlaylist() {
        let playlist = withObservationTracking {
            PlaylistService.shared.playlist
        } onChange: {
            self.observePlaylist()
        }
        
        assert(PlaylistService.shared.playlist == playlist)
        
        if validateCollection(PlaylistService.shared.playlist.entries, label: "PlaylistDataSource Playlist") {
            self.viewModels = playlist.entries
                .compactMap { $0 as? any PlaylistCellViewModelProducer }
                .map { $0.cellViewModel }
        } else {
            playlistTask?.cancel()
            playlistTask = Task {
                if let isCancelled = playlistTask?.isCancelled,
                   isCancelled {
                    return
                }
                Log(.info, "Received empty playlist, trying exponential backoff.")
                try await Task.sleep(nanoseconds: backoffTimer.nextWaitTime().nanoseconds)
                self.observePlaylist()
            }
        }
    }
    var playlistTask: Task<Void, any Error>?
    var backoffTimer = ExponentialBackoff(initialWaitTime: 0.3)
}
