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
///
/// ## Why there is no `Playcut` fixture here yet
///
/// `Playcut.stub()` lives in `PlaylistTesting`, a test-only `.library` product
/// that **no target in `WXYC.xcodeproj` links** — grep `project.pbxproj` for
/// `PlaylistTesting` and you get nothing. So app-target, watch-target, and
/// widget-extension `#Preview` blocks cannot call it, and each builds its
/// `Playcut` through `Playcut.init` with the canonical values from
/// `docs/test-fixtures.md` instead.
///
/// Linking `PlaylistTesting` into the shipping targets is the wrong fix: the
/// repo already settled this shape for the touring-show domain in
/// WXYC/wxyc-ios-64#771, where `ConcertsTesting` stayed test-only and a
/// `#if DEBUG` `Concert.previewFixture(…)` factory landed in the *shipping*
/// `Concerts` module instead. The equivalent for playcuts — a `#if DEBUG`
/// `Playcut.previewFixture(…)` in the shipping `Playlist` module, or a named
/// fixture on this type — is the open follow-up to WXYC/wxyc-ios-64#310. Until
/// one lands, the inline literals below the `#Preview` comments are the
/// convention.
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
