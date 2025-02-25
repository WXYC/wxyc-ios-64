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

protocol PlaylistCellViewModelProducer: Sendable {
    var cellViewModel: PlaylistCellViewModel { get }
}

typealias Cell = any UITableViewCell & Sendable & AnyObject

extension Playcut: PlaylistCellViewModelProducer {
    struct PlaycutCellConfigurator: CellConfigurator {
        let `class`: AnyClass = PlaycutCell.self
        
        let playcut: Playcut
        
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
                let artwork: UIImage =
                    await ArtworkService.shared.getArtwork(for: playcut)
                    ??  UIImage.logoImage
                
                playcutActivityItem.image = artwork
                cell.configure(with: artwork, token: playcut.id)
            }
            
            cell.activity = playcutActivityItem
        }
    }
    
    var cellViewModel: PlaylistCellViewModel {
        PlaylistCellViewModel(configuration: PlaycutCellConfigurator(playcut: self))
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
    struct BreakpointCellConfigurator: CellConfigurator {
        let `class`: AnyClass = BreakpointCell.self
        let breakpoint: Breakpoint
        
        func configure(_ cell: Cell) {
            guard let cell = cell as? BreakpointCell else {
                return
            }

            let timeSince1970 = Double(breakpoint.hour) / 1000.0
            let date = Date(timeIntervalSince1970: timeSince1970)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "h a"
            
            cell.timeLabel.text = dateFormatter.string(from: date)
        }
    }
    
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(
            configuration: BreakpointCellConfigurator(breakpoint: self)
        )
    }
}
