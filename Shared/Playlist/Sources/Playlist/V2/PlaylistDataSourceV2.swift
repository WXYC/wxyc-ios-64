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
///
/// This data source applies no encoding repair. The legacy v1 tubafrenzy server
/// double-encoded UTF-8 as Latin-1 and needed one; api.wxyc.org never has, and
/// the repair went with the v1 path (#262). `PlaylistDataSourceV2Tests`
/// pins that mojibake-shaped text is passed through uncorrected, so a
/// reintroduced repair would have to break a test rather than slip in.
public final class PlaylistDataSourceV2: PlaylistDataSource, @unchecked Sendable {
    private let transport: RevalidatingJSONDataSource<FlowsheetResponse>

    public init(session: URLSession = .shared) {
        self.transport = RevalidatingJSONDataSource(
            url: .WXYCFlowsheet,
            session: session,
            map: { FlowsheetConverter.convert($0.entries, onAir: $0.onAir) }
        )
    }

    public func getPlaylist() async throws -> Playlist {
        try await transport.getPlaylist()
    }
}
