//
//  PlaylistViewController.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import UIKit
import UI
import Core
import Spring

class PlaylistViewController: UITableViewController, PlaylistPresentable {
    var viewModels: [PlaylistCellViewModel] = []
    let playlistDataSource = PlaylistDataSource.shared
    var reuseIdentifiers: [String] = []
    
    override func viewDidLoad() {
        self.playlistDataSource.add(observer: self)
        self.tableView.rowHeight = UITableView.automaticDimension
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
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.viewModels.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let viewModel = self.viewModels[indexPath.row]
        
        if !self.reuseIdentifiers.contains(viewModel.reuseIdentifier) {
            tableView.register(viewModel.cellClass, forCellReuseIdentifier: viewModel.reuseIdentifier)
            self.reuseIdentifiers.append(viewModel.reuseIdentifier)
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: viewModel.reuseIdentifier, for: indexPath)
        viewModel.configure(cell)
        
        return cell
    }
}

typealias CellViewModel = PlaylistItem & PlaylistCellViewModelProducer

protocol PlaylistPresentable {
    func updateWith(viewModels: [PlaylistCellViewModel])
}

final class PlaylistDataSource {
    static let shared = PlaylistDataSource()
    
    init(playlistService: PlaylistService = .shared) {
        playlistService.getPlaylist().onSuccess(self.updateWith(playlist:))
    }
    
    func add(observer: PlaylistPresentable) {
        self.observers.append(observer)
        observer.updateWith(viewModels: self.cellViewModels)
    }
    
    private var observers: [PlaylistPresentable] = []
    
    private var cellViewModels: [PlaylistCellViewModel] = [] {
        didSet {
            self.updateObservers()
        }
    }
    
    private func updateWith(playlist: Playlist) {
        let items = playlist.playlistItems
        let filteredItems = items.lazy.compactMap { $0 as? CellViewModel }
        self.cellViewModels = filteredItems[\.cellViewModel]
    }
    
    func updateObservers() {
        DispatchQueue.main.async {
            for observer in self.observers {
                observer.updateWith(viewModels: self.cellViewModels)
            }
        }
    }
}

final class PlaylistCellViewModel {
    let cellClass: UITableViewCell.Type
    let reuseIdentifier: String
    let configure: (UITableViewCell) -> ()
    let artworkService = ArtworkService.shared
    
    init<Cell: UITableViewCell>(reuseIdentifier: String = NSStringFromClass(Cell.self), configure: @escaping (Cell) -> ()) {
        self.cellClass = Cell.self
        self.reuseIdentifier = reuseIdentifier
        
        self.configure = { cell in
            configure(cell as! Cell)
        }
    }
}

protocol PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel { get }
}

extension Playcut: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(configure: { (cell: PlaycutCell) in
            cell.artistLabel.text = self.artistName
            cell.songLabel.text = self.songTitle
            
            ArtworkService.shared.getArtwork(for: self).onSuccess { image in
                DispatchQueue.main.async {
                    cell.artworkImageView.image = image
                }
            }
        })
    }
}

extension Talkset: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(configure: { (cell: TalksetCell) in
            
        })
    }
}

extension Breakpoint: PlaylistCellViewModelProducer {
    var cellViewModel: PlaylistCellViewModel {
        return PlaylistCellViewModel(configure: { (cell: BreakpointCell) in
            
        })
    }
}

final class PlaycutCell: UITableViewCell {
    let artworkImageView = UIImageView()
    let artistLabel = UILabel()
    let songLabel = UILabel()
    let actionButton = UIButton()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        self.setUpViews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        self.setUpViews()
    }
    
    func setUpViews() {
        self.actionButton.setTitle("•••", for: .normal)
        
        self.fuckAutoResizingMaskConstraints()
        
        self.contentView.addSubview(self.artworkImageView)
        self.contentView.addSubview(self.artistLabel)
        self.contentView.addSubview(self.songLabel)
        self.contentView.addSubview(self.actionButton)
        
        let layoutMarginsGuide = self.contentView.layoutMarginsGuide
        
        self.contentView.addConstraints([
            layoutMarginsGuide.topAnchor.constraint(equalTo: self.artworkImageView.topAnchor),
            layoutMarginsGuide.trailingAnchor.constraint(equalTo: self.artworkImageView.trailingAnchor),
            layoutMarginsGuide.leadingAnchor.constraint(equalTo: self.artworkImageView.leadingAnchor),

            self.artworkImageView.widthAnchor.constraint(equalTo: self.artworkImageView.heightAnchor),
            
            self.actionButton.topAnchor.constraint(equalTo: self.artworkImageView.bottomAnchor),
            self.actionButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            self.actionButton.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            self.artistLabel.topAnchor.constraint(equalTo: self.artworkImageView.bottomAnchor),
            self.artistLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            self.artistLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),

            self.songLabel.topAnchor.constraint(equalTo: self.artistLabel.bottomAnchor),
            self.songLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            self.songLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            self.songLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            ])
    }
    // MARK: Overrides
    
    override func prepareForReuse() {
        self.artworkImageView.image = nil
    }
    
    // MARK: Private
    
    private func fuckAutoResizingMaskConstraints() {
        self.artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        self.artistLabel.translatesAutoresizingMaskIntoConstraints = false
        self.songLabel.translatesAutoresizingMaskIntoConstraints = false
        self.actionButton.translatesAutoresizingMaskIntoConstraints = false
    }
}

final class TalksetCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

final class BreakpointCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

extension Collection {
    subscript<T>(_ keyPath: KeyPath<Element, T>) -> [T] {
        return map { $0[keyPath: keyPath] }
    }
}
