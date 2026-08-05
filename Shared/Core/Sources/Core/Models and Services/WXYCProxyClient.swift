//
//  WXYCProxyClient.swift
//  Core
//
//  One authed-or-anonymous request/decode pipeline for api.wxyc.org's proxy
//  endpoints (#761). Replaces four hand-rolled copies of the same
//  baseURL → URLComponents-build → guard-let-url → authed-or-plain-fetch →
//  JSONDecoder.shared.decode pipeline: `Metadata.PlaycutMetadataService`,
//  `Metadata.DiscogsAPIEntityResolver`, and `Concerts.ConcertsFetcher`'s
//  `fetchConcerts`/`fetchConcert`. Each of those previously also carried its
//  own invalid-URL error case (`MetadataError.invalidURL`,
//  `ServiceError.noResults`, `ConcertsError.invalidURL`); this type has one,
//  ``WXYCProxyClient/ProxyError``.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// One `GET`-and-decode pipeline for `api.wxyc.org`'s proxy endpoints.
///
/// Builds a request from a path and query items against `baseURL`, attaches
/// a bearer token from `tokenProvider` when present, and decodes the
/// response with `JSONDecoder.shared`. Authentication and the 401
/// reauthenticate-and-retry-once behavior are delegated entirely to
/// `URLSession.authedData(for:tokenProvider:)`, which already sends a plain
/// unauthenticated request when `tokenProvider` is `nil` — so this type never
/// needs to branch on whether a token provider was supplied, unlike the
/// per-service `WebSession`/`URLSession` dual-field pattern it replaces.
public struct WXYCProxyClient: Sendable {
    /// The single error this client throws beyond whatever `session`,
    /// `tokenProvider`, or the JSON decode throw.
    public enum ProxyError: Error, Equatable {
        /// `path` and `query` could not be composed into a valid URL against
        /// `baseURL`.
        case invalidURL
    }

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: SessionTokenProvider?

    /// - Parameters:
    ///   - baseURL: The proxy's base URL. Defaults to `https://api.wxyc.org`.
    ///   - session: The `URLSession` to issue requests on. Defaults to `.shared`.
    ///   - tokenProvider: Supplies the anonymous-session bearer token. When
    ///     `nil`, requests are sent unauthenticated — useful in tests behind a
    ///     stub `URLProtocol`, or for call sites that don't yet have a
    ///     configured session.
    public init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        session: URLSession = .shared,
        tokenProvider: SessionTokenProvider? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// Issues a `GET` request against `baseURL.appending(path: path)`,
    /// carrying `query` as URL query items, and decodes the response as `T`.
    ///
    /// - Parameters:
    ///   - path: Appended to `baseURL`, e.g. `"proxy/metadata/album"` or
    ///     `"concerts/\(id)"`.
    ///   - query: URL query items. Omit (or pass `[]`) for a path with no
    ///     query string — matches ``Concerts/ConcertsFetcher/fetchConcert(id:)``'s
    ///     bare-path request.
    /// - Returns: The decoded `T`.
    /// - Throws: ``ProxyError/invalidURL`` if `path`/`query` don't compose
    ///   into a valid URL; otherwise whatever
    ///   `URLSession.authedData(for:tokenProvider:)` or the JSON decode
    ///   throw (notably ``HTTPStatusError`` for a non-2xx response).
    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw ProxyError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, _) = try await session.authedData(for: request, tokenProvider: tokenProvider)
        return try JSONDecoder.shared.decode(T.self, from: data)
    }
}

extension WXYCProxyClient.ProxyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The request URL could not be constructed."
        }
    }
}
