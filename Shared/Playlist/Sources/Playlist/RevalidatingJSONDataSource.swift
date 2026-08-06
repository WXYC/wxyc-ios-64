//
//  RevalidatingJSONDataSource.swift
//  Playlist
//
//  Generic HTTP transport shared by PlaylistDataSourceV1 and PlaylistDataSourceV2:
//  issue a GET with a revalidating cache policy, validate the response, decode
//  the wire shape, and hand it to a caller-supplied map to produce a Playlist.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core

/// Fetches and decodes a `Playlist` from a single URL.
///
/// `PlaylistDataSourceV1` and `PlaylistDataSourceV2` were the same class
/// modulo URL constant, an optional mojibake repair, and the final decode/map
/// step. This generic factors out everything except the decode target:
/// `Response` is the wire shape (`Playlist` itself for v1, `FlowsheetResponse`
/// for v2) and `map` converts it to the canonical `Playlist`.
///
/// The v2 flowsheet decoder stays hand-written under its own parity-test guard
/// (see docs/code-generation.md) — this type only wraps transport (URL, cache
/// policy, timeout, status validation, generic `Decodable` dispatch), never
/// decode logic itself.
final class RevalidatingJSONDataSource<Response: Decodable>: PlaylistDataSource, @unchecked Sendable {
    private let url: URL
    private let session: URLSession
    private let repairsMojibake: Bool
    private let map: @Sendable (Response) -> Playlist

    /// - Parameters:
    ///   - url: The endpoint to poll.
    ///   - session: The `URLSession` to issue the request on.
    ///   - repairsMojibake: Whether to run `Data.repairingMojibake()` on the
    ///     raw response body before decoding. Only the legacy v1 tubafrenzy
    ///     API needs this (see `repairingMojibake()`'s doc comment); the v2
    ///     flowsheet API has never exhibited the underlying UTF-8-as-Latin-1
    ///     double-encoding bug, so `PlaylistDataSourceV2` leaves this `false`.
    ///     Defaults to `false`.
    ///   - map: Converts the decoded `Response` into the canonical `Playlist`.
    init(
        url: URL,
        session: URLSession,
        repairsMojibake: Bool = false,
        map: @escaping @Sendable (Response) -> Playlist
    ) {
        self.url = url
        self.session = session
        self.repairsMojibake = repairsMojibake
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
        let decodableData = repairsMojibake ? data.repairingMojibake() : data
        let decoded = try JSONDecoder.shared.decode(Response.self, from: decodableData)
        return map(decoded)
    }
}
