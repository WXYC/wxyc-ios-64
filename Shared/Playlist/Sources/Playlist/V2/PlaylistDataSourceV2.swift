//
//  PlaylistDataSourceV2.swift
//  Playlist
//
//  Data source for the v2 flowsheet API.
//

import Foundation
import Analytics

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
        do {
            let (data, _) = try await session.data(from: URL.WXYCFlowsheet)
            let decoder = JSONDecoder()
            let entries = try decoder.decode([FlowsheetEntry].self, from: data)
            return FlowsheetConverter.convert(entries)
        } catch let error as NSError {
            throw AnalyticsOSError(
                domain: error.domain,
                code: error.code,
                description: error.localizedDescription
            )
        } catch let error as DecodingError {
            throw AnalyticsDecoderError(description: error.localizedDescription)
        }
    }
}
