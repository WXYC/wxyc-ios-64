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

protocol PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel { get }
}

extension Playcut: PlaylistCellViewModelProducer {
    @MainActor
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel { (cell: PlaycutCell) in
            cell.token = self.id
            cell.artistLabel.text = self.artistName
            cell.songLabel.text = self.songTitle
            
            let playcutActivityItem = PlaycutActivityItem(playcut: self)
            
            Task {
                let artwork: UIImage =
                    await ArtworkService.shared.getArtwork(for: self) ??  #imageLiteral(resourceName: "logo.pdf")
                
                playcutActivityItem.image = artwork
                cell.configure(with: artwork, token: self.id)
            }
            
            cell.activity = playcutActivityItem
        }
    }
}

extension Talkset: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel { (_: TalksetCell) in }
    }
}

extension Breakpoint: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel { (cell: BreakpointCell) in
            let timeSince1970 = Double(self.hour) / 1000.0
            let date = Date(timeIntervalSince1970: timeSince1970)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "h a"
            
            cell.timeLabel.text = dateFormatter.string(from: date)
        }
    }
}
