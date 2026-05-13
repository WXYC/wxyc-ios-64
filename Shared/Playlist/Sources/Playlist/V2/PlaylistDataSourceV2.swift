//
//  PlaylistDataSourceV2.swift
//  Playlist
//
//  Data source for the v2 flowsheet API.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core

/// URL for the v2 flowsheet API.
extension URL {
    static let WXYCFlowsheet = URL(string: "https://api.wxyc.org/flowsheet")!
}

/// Data source that fetches playlists from the v2 flowsheet API.
public final class PlaylistDataSourceV2: PlaylistDataSource, @unchecked Sendable {
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
            url: URL.WXYCFlowsheet,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        )
        let (data, response) = try await session.data(for: request)
        try (response as? HTTPURLResponse)?.validateSuccessStatus()
        let flowsheet = try JSONDecoder.shared.decode(FlowsheetResponse.self, from: data)
        return FlowsheetConverter.convert(flowsheet.entries)
    }
}
