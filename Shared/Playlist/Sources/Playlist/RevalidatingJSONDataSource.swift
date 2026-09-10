//
//  RevalidatingJSONDataSource.swift
//  Playlist
//
//  Generic HTTP transport for the flowsheet API: issue a GET with a revalidating
//  cache policy, validate the response, decode the wire shape, and hand it to a
//  caller-supplied map to produce a Playlist.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core

/// Fetches and decodes a `Playlist` from a single URL.
///
/// Factors transport out of decoding: `Response` is the wire shape
/// (`FlowsheetResponse`) and `map` converts it to the canonical `Playlist`.
///
/// This was extracted when `PlaylistDataSourceV1` and `PlaylistDataSourceV2`
/// were the same class modulo URL constant and decode target. The v1 half is
/// gone (#262) and only one conformer remains, but the seam is kept
/// deliberately: it is what lets `RevalidatingJSONDataSourceTests` pin the
/// cache policy and status validation without going through
/// `FlowsheetConverter`.
///
/// The v2 flowsheet decoder stays hand-written under its own parity-test guard
/// (see docs/code-generation.md) — this type only wraps transport (URL, cache
/// policy, timeout, status validation, generic `Decodable` dispatch), never
/// decode logic itself.
final class RevalidatingJSONDataSource<Response: Decodable>: PlaylistDataSource, @unchecked Sendable {
    private let url: URL
    private let session: URLSession
    private let map: @Sendable (Response) -> Playlist

    /// - Parameters:
    ///   - url: The endpoint to poll.
    ///   - session: The `URLSession` to issue the request on.
    ///   - map: Converts the decoded `Response` into the canonical `Playlist`.
    init(
        url: URL,
        session: URLSession,
        map: @escaping @Sendable (Response) -> Playlist
    ) {
        self.url = url
        self.session = session
        self.map = map
    }

    func getPlaylist() async throws -> Playlist {
        // .reloadRevalidatingCacheData forces URLSession to consult the origin server
        // on every poll. Without it, URLCache.shared can replay the previous process's
        // stored response (zero network traffic) for as long as the server's
        // Cache-Control: max-age window lasts, leaving the UI stuck on stale data
        // after relaunch.
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        )
        let (data, response) = try await session.data(for: request)
        try (response as? HTTPURLResponse)?.validateSuccessStatus()
        let decoded = try JSONDecoder.shared.decode(Response.self, from: data)
        return map(decoded)
    }
}
