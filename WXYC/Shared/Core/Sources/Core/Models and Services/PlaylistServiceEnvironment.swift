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

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    var playlistService: PlaylistService? {
        get { self[PlaylistServiceKey.self] }
        set { self[PlaylistServiceKey.self] = newValue }
    }
}


