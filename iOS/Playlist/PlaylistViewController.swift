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
        self.tableView.backgroundColor = .clear
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
    
    private static let header: PlayerHeader = {
        let header = PlayerHeader()
        
        let view = UIView()
        view.backgroundColor = .clear
        header.backgroundView = view

        return header
    }()
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let size = PlaylistViewController.header.systemLayoutSizeFitting(
            tableView.bounds.size,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .defaultHigh
        )
        
        return size.height
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return PlaylistViewController.header
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
