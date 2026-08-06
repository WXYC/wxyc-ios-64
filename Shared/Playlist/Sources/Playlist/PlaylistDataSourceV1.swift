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
///
/// The v1 API's response *is* the canonical `Playlist` shape, so the
/// `RevalidatingJSONDataSource` map is the identity function. `repairsMojibake`
/// is `true` here: the legacy tubafrenzy server has historically double-encoded
/// UTF-8 as Latin-1 (see `Data.repairingMojibake()`'s doc comment).
public final class PlaylistDataSourceV1: PlaylistDataSource, @unchecked Sendable {
    private let transport: RevalidatingJSONDataSource<Playlist>

    public init(session: URLSession = .shared) {
        self.transport = RevalidatingJSONDataSource(
            url: .WXYCPlaylist,
            session: session,
            repairsMojibake: true,
            map: { $0 }
        )
    }

    public func getPlaylist() async throws -> Playlist {
        try await transport.getPlaylist()
    }
}
