//
//  PlaylistViewController.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import UIKit
import Observation
import Core
import Logger

class PlaylistViewController: UITableViewController, PlaycutShareDelegate {
    var viewModels: [PlaylistCellViewModel] = []
    let playlistDataSource = PlaylistDataSource.shared
    var reuseIdentifiers: Set<String> = []
    
    override func viewDidLoad() {
        self.observePlaylistDataSource()
        self.setUpTableView()
    }
    
    func observePlaylistDataSource() {
        self.playlistDataSource.observe { viewModels in
            validateCollection(viewModels, label: "\(Self.self) [PlaylistCellViewModel]")
            self.update(viewModels: viewModels)
        }
    }
    
    private func setUpTableView() {
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 500
        self.tableView.sectionHeaderHeight = UITableView.automaticDimension
        self.tableView.estimatedSectionHeaderHeight = 222
        self.tableView.backgroundColor = .clear
        self.tableView.contentOffset = .zero
        self.tableView.allowsSelection = false
        self.tableView.separatorStyle = .none
        
        let nib = UINib(nibName: NSStringFromClass(PlayerHeader.self), bundle: nil)
        self.tableView.register(nib, forHeaderFooterViewReuseIdentifier: NSStringFromClass(PlayerHeader.self))
    }
    
    // MARK: PlaylistPresentable
    
    func update(viewModels: [PlaylistCellViewModel]) {
        self.viewModels = viewModels
        self.tableView.reloadData()
    }
    
    // MARK: PlaycutShareDelegate
    
    func presentShareSheet(for activity: PlaycutActivityItem, from view: UIView) {
        let activityViewController = UIActivityViewController(activityItems: [activity.image ?? #imageLiteral(resourceName: "logo"), activity.activityTitle!, URL(string: "http://wxyc.org")!], applicationActivities: [])
        activityViewController.popoverPresentationController?.sourceView = view
        self.present(activityViewController, animated: true)
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
            let nib = UINib(nibName: viewModel.class, bundle: nil)
            tableView.register(nib, forCellReuseIdentifier: viewModel.class)
            self.reuseIdentifiers.insert(viewModel.reuseIdentifier)
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: viewModel.reuseIdentifier, for: indexPath)
        viewModel.configure(cell)
        cell.backgroundColor = .clear
        
        if let playcutCell = cell as? PlaycutCell {
            playcutCell.delegate = self
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard tableView.numberOfRows(inSection: section) > 0 else {
            Log(.error, "No rows in section \(section)")
            return nil
        }
        
        let button = UIButton(type: .custom)
        button.setTitle("what the freq?", for: .normal)
        return button
    }
}
