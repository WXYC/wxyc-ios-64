//
//  Playlister.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/20/25.
//

import Foundation
import Core

@MainActor
@Observable
final class Playlister {
    var playlist: Playlist = .empty
    
    init() {
        PlaylistService.shared.observe { playlist in
            self.playlist = playlist
        }
    }
}
