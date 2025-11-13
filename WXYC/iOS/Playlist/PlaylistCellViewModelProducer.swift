//
//  PlaylistCellViewModelProducer.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation
import Core
import UIKit
import Logger

protocol PlaylistCellViewModelProducer: Sendable {
    var cellViewModel: PlaylistCellViewModel { get }
}

typealias Cell = any UITableViewCell & Sendable & AnyObject

extension Playcut: PlaylistCellViewModelProducer {
    struct PlaycutCellConfigurator: CellConfigurator {
        let `class`: AnyClass = PlaycutCell.self

        let playcut: Playcut
        let artworkService: MultisourceArtworkService

        @MainActor
        func configure(_ cell: Cell) {
            guard let cell = cell as? PlaycutCell else {
                return
            }

            cell.token = playcut.id
            cell.artistLabel.text = playcut.artistName
            cell.songLabel.text = playcut.songTitle

            let playcutActivityItem = PlaycutActivityItem(playcut: playcut)

            Task {
                let timer = Timer.start()
                let artwork: UIImage
                
                do {
                    artwork =
                        try await artworkService.fetchArtwork(for: playcut)
                    Log(.info, "Artwork fetched for playcut \(playcut.id) after \(timer.duration()) seconds")
                } catch {
                    artwork = UIImage.logoImage
                }

                playcutActivityItem.image = artwork
                cell.configure(with: artwork, token: playcut.id)
            }

            cell.activity = playcutActivityItem
        }
    }

    var cellViewModel: PlaylistCellViewModel {
        // Create a fresh service instance - caching is handled internally
        PlaylistCellViewModel(configuration: PlaycutCellConfigurator(
            playcut: self,
            artworkService: MultisourceArtworkService()
        ))
    }
}

extension Talkset: PlaylistCellViewModelProducer {
    struct TalksetCellConfigurator: CellConfigurator {
        let `class`: AnyClass = TalksetCell.self
        
        func configure(_ cell: Cell) {
            guard let cell = cell as? TalksetCell else {
                return
            }

            cell.talksetLabel.text = "Talkset"
        }
    }
    
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(
            configuration: TalksetCellConfigurator()
        )
    }
}

extension Breakpoint: PlaylistCellViewModelProducer {
    struct Configurator: CellConfigurator {
        let `class`: AnyClass = BreakpointCell.self
        let breakpoint: Breakpoint
        
        func configure(_ cell: Cell) {
            guard let cell = cell as? BreakpointCell else {
                return
            }

            cell.timeLabel.text = breakpoint.formattedDate
        }
    }
    
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(
            configuration: Configurator(breakpoint: self)
        )
    }
}
