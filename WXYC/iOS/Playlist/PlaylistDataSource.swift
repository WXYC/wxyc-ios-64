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
final class PlaylistDataSource: Sendable {
    init(playlistService: PlaylistService) {
        Task {
            for await playlist in playlistService {
                self.viewModels = playlist.entries
                    .compactMap { $0 as? any PlaylistCellViewModelProducer }
                    .map { $0.cellViewModel }
            }
        }
    }

    typealias Observer = @MainActor @Sendable ([PlaylistCellViewModel]) -> ()
    @MainActor private var observers: [Observer] = []

    @MainActor
    func observe(_ observer: @escaping Observer) {
        observer(self.viewModels)
        self.observers.append(observer)
    }

    // MARK: Private

    private(set) var viewModels: [PlaylistCellViewModel] = [] {
        didSet {
            for o in observers {
                o(self.viewModels)
            }
        }
    }
}
