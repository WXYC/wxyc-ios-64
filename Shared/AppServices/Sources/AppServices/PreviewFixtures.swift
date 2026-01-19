//
//  PreviewFixtures.swift
//  AppServices
//
//  Shared preview fixtures for SwiftUI previews to ensure consistent
//  behavior across all preview blocks.
//
//  Created by Jake Bromberg on 01/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import Artwork

// MARK: - Preview Fixtures

/// Shared preview instances for consistent SwiftUI preview behavior.
/// Using shared instances ensures previews behave consistently and
/// reduces the overhead of creating new service instances per preview.
public enum PreviewFixtures {
    /// Shared PlaylistService for previews
    public static let playlistService = PlaylistService()
    
    /// Shared MultisourceArtworkService for previews
    public static let artworkService = MultisourceArtworkService()
}

// MARK: - Convenience Extensions

public extension PlaylistService {
    /// Shared preview instance
    static var preview: PlaylistService { PreviewFixtures.playlistService }
}

public extension MultisourceArtworkService {
    /// Shared preview instance
    static var preview: MultisourceArtworkService { PreviewFixtures.artworkService }
}
