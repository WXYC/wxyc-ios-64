//
//  MockPlaylistFetcher.swift
//  PlaylistTesting
//
//  Test double for PlaylistFetcherProtocol that returns configurable playlists.
//  Replaces the identical MockPlaylistFetcher classes in PlaylistTests and AppServicesTests.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@_exported import Playlist

/// Test double for ``PlaylistFetcherProtocol`` that returns a configurable playlist.
///
/// ```swift
/// let fetcher = MockPlaylistFetcher()
/// fetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "la paradoja")])
/// let playlist = await fetcher.fetchPlaylist()
/// #expect(fetcher.callCount == 1)
/// ```
public final class MockPlaylistFetcher: PlaylistFetcherProtocol, @unchecked Sendable {
    /// The playlist to return from ``fetchPlaylist()``.
    public var playlistToReturn: Playlist = .empty

    /// The number of times ``fetchPlaylist()`` has been called.
    public var callCount = 0

    public init() {}

    public func fetchPlaylist() async -> Playlist {
        callCount += 1
        return playlistToReturn
    }
}

/// Test double for ``PlaylistDataSource`` that returns a configurable playlist or throws.
///
/// ```swift
/// let dataSource = MockPlaylistDataSource()
/// dataSource.playlistToReturn = .stub(playcuts: [.stub(songTitle: "VI Scose Poise")])
/// let playlist = try await dataSource.getPlaylist()
/// #expect(dataSource.fetchCount == 1)
/// ```
public final class MockPlaylistDataSource: PlaylistDataSource, @unchecked Sendable {
    /// The playlist to return from ``getPlaylist()``.
    public var playlistToReturn: Playlist = .empty

    /// An error to throw from ``getPlaylist()``, if set.
    public var errorToThrow: Error?

    /// The number of times ``getPlaylist()`` has been called.
    public var fetchCount = 0

    public init() {}

    public func getPlaylist() async throws -> Playlist {
        fetchCount += 1

        if let error = errorToThrow {
            throw error
        }

        return playlistToReturn
    }
}
