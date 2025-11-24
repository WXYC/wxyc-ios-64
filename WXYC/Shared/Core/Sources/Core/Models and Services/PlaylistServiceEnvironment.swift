//
//  PlaylistServiceEnvironment.swift
//  Core
//
//  SwiftUI Environment support for PlaylistService
//

import SwiftUI

// MARK: - Environment Key

private struct PlaylistServiceKey: EnvironmentKey {
    static let defaultValue: PlaylistService? = nil
}

private struct ArtworkServiceKey: EnvironmentKey {
    static let defaultValue: MultisourceArtworkService? = nil
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    var playlistService: PlaylistService? {
        get { self[PlaylistServiceKey.self] }
        set { self[PlaylistServiceKey.self] = newValue }
    }
    
    var artworkService: MultisourceArtworkService? {
        get { self[ArtworkServiceKey.self] }
        set { self[ArtworkServiceKey.self] = newValue }
    }
}


