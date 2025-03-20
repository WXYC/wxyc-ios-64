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
    static let shared = PlaylistDataSource()

    init(playlistService: PlaylistService = .shared) {
        PlaylistService.shared.observe { playlist in
            self.viewModels = playlist.entries
                .compactMap { $0 as? any PlaylistCellViewModelProducer }
                .map { $0.cellViewModel }
        }
    }
        
    public typealias Observer = @MainActor @Sendable ([PlaylistCellViewModel]) -> ()
    @MainActor private var observers: [Observer] = []
    
    @MainActor
    public func observe(_ observer: @escaping Observer) {
        Task { @MainActor in
            observer(self.viewModels)
            self.observers.append(observer)
        }
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
