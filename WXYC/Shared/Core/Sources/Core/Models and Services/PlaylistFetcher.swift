//
//  PlaylistFetcher.swift
//  Core
//
//  Created by Jake Bromberg on 11/8/25.
//

import Foundation
import Analytics

public protocol PlaylistFetcher: Sendable {
    func getPlaylist() async throws -> Playlist
}

private let decoder = JSONDecoder()

extension URLSession: PlaylistFetcher {
    public func getPlaylist() async throws -> Playlist {
        do {
            let playlistData = try Data.init(contentsOf: URL.WXYCPlaylist)
//            let playlistData = playlistString.data(using: .utf8)
//            let (playlistData, _) = try await self.data(from: URL.WXYCPlaylist)
            return try decoder.decode(Playlist.self, from: playlistData)
        } catch let error as NSError {
            print(error.localizedDescription)
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
