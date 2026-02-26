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
        let (data, _) = try await session.data(from: URL.WXYCFlowsheet)
        let decoder = JSONDecoder()
        let entries = try decoder.decode([FlowsheetEntry].self, from: data)
        return FlowsheetConverter.convert(entries)
    }
}
