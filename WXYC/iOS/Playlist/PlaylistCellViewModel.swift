//
//  PlaylistCellViewModel.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import UIKit
import Core

protocol CellConfigurator: Sendable {
    var `class`: AnyClass { get }
    
    @MainActor
    func configure(_ cell: UITableViewCell & Sendable & AnyObject)
}

final class PlaylistCellViewModel: Sendable {
    let reuseIdentifier: String
    let `class`: String
    private let configuration: any CellConfigurator
    
    init<C: CellConfigurator>(
        configuration: C
    ) {
        self.reuseIdentifier = NSStringFromClass(configuration.class)
        self.class = NSStringFromClass(configuration.class)
        self.configuration = configuration
    }

    @MainActor
    func configure<Cell: UITableViewCell & Sendable>(_ cell: Cell) {
        configuration.configure(cell)
    }
}

extension UITableViewCell: @retroactive Sendable {
    
}
