//
//  PlaylistCellViewModelProducer.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation
import Core

protocol PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel { get }
}

extension Playcut: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(configure: { (cell: PlaycutCell) in
            cell.token = self.id
            cell.artistLabel.text = self.artistName
            cell.songLabel.text = self.songTitle
            
            let playcutActivityItem = PlaycutActivityItem(playcut: self)
            
            cell.artworkRequest = ArtworkService.shared.getArtwork(for: self).onSuccess { image in
                playcutActivityItem.image = image
                
                cell.configure(with: image, token: self.id)
            }
            
            cell.activity = playcutActivityItem
        })
    }
}

extension Talkset: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(configure: { (_: TalksetCell) in })
    }
}

extension Breakpoint: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(configure: { (cell: BreakpointCell) in
            let timeSince1970 = Double(self.hour) / 1000.0
            let date = Date(timeIntervalSince1970: timeSince1970)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "h a"
            
            cell.timeLabel.text = dateFormatter.string(from: date)
        })
    }
}
