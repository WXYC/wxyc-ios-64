//
//  PlaylistCellViewModel.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import UIKit
import Core

final class PlaylistCellViewModel: Sendable {
    let cellClass: UITableViewCell.Type
    let reuseIdentifier: String
    let configure: (UITableViewCell) -> ()
    let artworkService = ArtworkService.shared
    
    init<Cell: UITableViewCell>(
        reuseIdentifier: String = NSStringFromClass(Cell.self),
        configure: @escaping (Cell) -> ()
    ) {
        self.cellClass = Cell.self
        self.reuseIdentifier = reuseIdentifier
        
        self.configure = { cell in
            configure(cell as! Cell)
        }
    }
}
