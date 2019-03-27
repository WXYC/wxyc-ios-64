//
//  PlaylistViewController.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import UIKit
import Core

class PlaylistViewController: UITableViewController, PlaylistPresentable {
    var viewModels: [PlaylistCellViewModel] = []
    let playlistDataSource = PlaylistDataSource.shared
    var reuseIdentifiers: [String] = []
    
    override func viewDidLoad() {
        self.playlistDataSource.add(observer: self)
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.sectionHeaderHeight = UITableView.automaticDimension
        self.tableView.estimatedSectionHeaderHeight = 222
        self.tableView.backgroundColor = .clear
        
        let nib = UINib(nibName: NSStringFromClass(PlayerHeader.self), bundle: nil)
        self.tableView.register(nib, forHeaderFooterViewReuseIdentifier: NSStringFromClass(PlayerHeader.self))
    }
    
    // MARK: PlaylistPresentable
    
    func updateWith(viewModels: [PlaylistCellViewModel]) {
        self.viewModels = viewModels
        self.tableView.reloadData()
    }
    
    // MARK: UITableViewController
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return tableView.dequeueReusableHeaderFooterView(withIdentifier: NSStringFromClass(PlayerHeader.self))
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.viewModels.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let viewModel = self.viewModels[indexPath.row]
        
        if !self.reuseIdentifiers.contains(viewModel.reuseIdentifier) {
            let className = NSStringFromClass(viewModel.cellClass)
            let nib = UINib(nibName: className, bundle: nil)
            
            tableView.register(nib, forCellReuseIdentifier: className)

            self.reuseIdentifiers.append(viewModel.reuseIdentifier)
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: viewModel.reuseIdentifier, for: indexPath)
        viewModel.configure(cell)
        cell.backgroundColor = .clear
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard tableView.numberOfRows(inSection: section) > 0 else {
            return nil
        }
        
        let button = UIButton(type: .custom)
        button.setTitle("what the freq?", for: .normal)
        return button
    }
}
