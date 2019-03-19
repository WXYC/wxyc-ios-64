//
//  PlaylistDataSource.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import Foundation
import Core

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
