//
//  PlaylistDataSourceV1.swift
//  Playlist
//
//  Data source for the v1 (legacy tubafrenzy) playlist API. Issues each poll
//  with `.reloadRevalidatingCacheData` so URLCache.shared cannot replay a stale
//  response across app launches.
//
//  Created by Jake Bromberg on 05/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core

/// Data source that fetches playlists from the v1 (legacy tubafrenzy) flowsheet API.
public final class PlaylistDataSourceV1: PlaylistDataSource, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func getPlaylist() async throws -> Playlist {
        // .reloadRevalidatingCacheData forces URLSession to consult the origin server
        // on every poll. Without it, URLCache.shared can replay the previous process's
        // stored response (zero network traffic) for as long as the server's
        // Cache-Control: max-age window lasts, leaving the UI stuck on stale data
        // after relaunch.
        let request = URLRequest(
            url: URL.WXYCPlaylist,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        )
        let (playlistData, response) = try await session.data(for: request)
        try (response as? HTTPURLResponse)?.validateSuccessStatus()
        let repairedData = playlistData.repairingMojibake()
        return try JSONDecoder.shared.decode(Playlist.self, from: repairedData)
    }
}
