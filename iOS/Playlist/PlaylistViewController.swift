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

protocol PlaylistPresentable {
    func updateWith(viewModels: [PlaylistCellViewModel])
}

final class PlaylistDataSource {
    typealias CellViewModel = PlaylistItem & PlaylistCellViewModelProducer
    
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
    
    private var playlistItems: [PlaylistItem] = []
    
    private func updateWith(playlist: Playlist) {
        if self.playlistItems == playlist.playlistItems {
            return
        }
        
        self.playlistItems = playlist.playlistItems
        let filteredItems = self.playlistItems.lazy.compactMap { $0 as? CellViewModel }
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
            cell.token = AnyEquatable(value: self.id)
            cell.artistLabel.text = self.artistName
            cell.songLabel.text = self.songTitle
            
            let playcutActivityItem = PlaycutActivityItem(playcut: self)
            
            ArtworkService.shared.getArtwork(for: self).onSuccess { image in
                playcutActivityItem.image = image
                
                cell.configure(with: image, token: AnyEquatable(value: self.id))
            }
            
            cell.activity = playcutActivityItem
        })
    }
}

extension UIActivity.ActivityType {
    static let wxyc = UIActivity.ActivityType("org.wxyc")
}


final class PlaycutActivityItem: UIActivity {
    let playcut: Playcut
    var image: UIImage?
    
    init(playcut: Playcut) {
        self.playcut = playcut
    }
    
    override class var activityCategory: UIActivity.Category {
        return .share
    }
    
    override var activityType: UIActivity.ActivityType? {
        return .wxyc
    }
    
    override var activityImage: UIImage? {
        return self.image
    }
    
    override var activityTitle: String? {
        return "\(self.playcut.songTitle) by \(self.playcut.artistName)"
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        for case is UIImage in activityItems {
            return true
        }
        
        return false
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

struct AnyEquatable: Equatable {
    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        return lhs.equation(rhs.value)
    }
    
    let value: Any
    private let equation: (Any) -> Bool
    
    init<T: Equatable>(value: T) {
        self.value = value
        
        self.equation = { x in
            guard let x = x as? T else {
                return false
            }
            
            return x == value
        }
    }
}
