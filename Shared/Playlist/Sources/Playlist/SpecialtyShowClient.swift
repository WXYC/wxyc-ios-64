//
//  SpecialtyShowClient.swift
//  Playlist
//
//  Reads `GET /specialty-shows`, honoring its 5-minute cache window and its ETag.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core

/// Fetches the specialty-show catalog and caches it in memory.
///
/// Inside the 5-minute window (the endpoint's `Cache-Control: public, max-age=300`) a call makes no
/// request. After it, the call revalidates with `If-None-Match`; a 304 keeps the cached catalog and
/// restarts the window, a 200 replaces both the catalog and the ETag. A failed request throws and
/// leaves the cache as it was.
public actor SpecialtyShowClient {
    /// How long a fetched catalog is served without asking the server.
    public static let cacheWindow: TimeInterval = 300

    private let baseURL: URL
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var cached: (shows: [SpecialtyShow], etag: String?, fetchedAt: Date)?

    /// - Parameters:
    ///   - baseURL: Backend-Service base URL. Defaults to `https://api.wxyc.org`.
    ///   - session: The `URLSession` to issue requests on.
    ///   - now: The clock the cache window is measured against.
    public init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.now = now
    }

    /// The active specialty shows, from the cache when it is still fresh.
    public func shows() async throws -> [SpecialtyShow] {
        if let cached, now().timeIntervalSince(cached.fetchedAt) < Self.cacheWindow {
            return cached.shows
        }

        // The cache is ours; keep URLCache out of it so a 304 reaches this code.
        var request = URLRequest(url: baseURL.appending(path: "specialty-shows"), cachePolicy: .reloadIgnoringLocalCacheData)
        if let etag = cached?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse

        if http?.statusCode == 304, let cached {
            self.cached = (cached.shows, cached.etag, now())
            return cached.shows
        }
        try http?.validateSuccessStatus()
        let shows = try JSONDecoder.shared.decode([SpecialtyShow].self, from: data)
        cached = (shows, http?.value(forHTTPHeaderField: "ETag"), now())
        return shows
    }
}
