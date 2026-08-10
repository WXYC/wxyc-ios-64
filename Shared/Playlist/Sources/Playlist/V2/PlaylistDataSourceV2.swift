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
///
/// **The window and the display order are keyed differently.** Backend selects
/// the page with `ORDER BY flowsheet.id DESC` (`getEntriesByPage`), while
/// ``Playlist/entries`` re-sorts what arrives by `(chronOrderID, id)` — the
/// composite `(show_id, play_order)` key that surfaces dj-site reorders (#839).
/// So this is "the newest 50 rows by insertion, shown in play order", not "the
/// newest 50 in play order": after a reorder, a row displayed at the tail may
/// not be the oldest one in play order, and a row just outside the window could
/// belong above one inside it. Harmless at a 50-row window where a show is
/// ~20 entries and reorders move rows by one or two places; worth knowing
/// before anyone builds pagination on top of the displayed order.
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
        return FlowsheetConverter.convert(flowsheet.entries, onAir: flowsheet.onAir)
    }
}
