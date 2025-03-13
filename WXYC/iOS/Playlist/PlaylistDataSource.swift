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
        Task { await self.observePlaylist() }
    }
    
    // MARK: Private
    
    private(set) var viewModels: [PlaylistCellViewModel] = []
    
    private func observePlaylist() async {
        let playlistTask = withObservationTracking {
            Task {
                await PlaylistService.shared.playlist
            }
        } onChange: {
            Task { await self.observePlaylist() }
        }
        
        let playlist = await playlistTask.value
        
        if await validateCollection(PlaylistService.shared.playlist.entries, label: "PlaylistDataSource Playlist") {
            self.backoffTimer.reset()
            PostHogSDK.shared.capture(
                "viewModels loaded",
                properties: [
                    "attempts" : self.backoffTimer.numberOfAttempts,
                    "total wait time" : self.backoffTimer.totalWaitTime,
                ]
            )
            self.viewModels = playlist.entries
                .compactMap { $0 as? any PlaylistCellViewModelProducer }
                .map { $0.cellViewModel }
        } else {
            let waitTime = self.backoffTimer.nextWaitTime()
            Log(.info, "Received empty playlist, trying exponential backoff: \(self.backoffTimer).")
            try? await Task.sleep(nanoseconds: waitTime.nanoseconds)
            await self.observePlaylist()
        }
    }

    var backoffTimer = ExponentialBackoff(initialWaitTime: 0.3)
}
