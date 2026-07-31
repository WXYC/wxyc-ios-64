//
//  URLSession+AuthedRequest.swift
//  Core
//
//  Shared request seam for backend proxy endpoints that require the
//  anonymous-session bearer token: attaches the token, and on a 401 response
//  forces a fresh token via `SessionTokenProvider.reauthenticate()` and
//  retries the request exactly once. `Concerts.ConcertsFetcher` and the
//  `Metadata` package's proxy calls depend on `Core` but not on
//  `MusicShareKit` (the concrete `AuthenticationService`), so the retry
//  capability is expressed entirely through the `SessionTokenProvider`
//  protocol. Mirrors the reauthenticate-then-retry-once pattern in
//  `MusicShareKit.RequestService`, minus its bespoke 403 shadow-ban handling.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension URLSession {
    /// Sends `request`, attaching a `Bearer` token from `tokenProvider` when
    /// present, and retries exactly once on a 401 response after forcing a
    /// fresh token.
    ///
    /// - When `tokenProvider` is `nil`, the request is sent unauthenticated
    ///   with no retry — matches the "optional token provider" convention
    ///   used by `ConcertsFetcher`, `PlaycutMetadataService`, and
    ///   `DiscogsAPIEntityResolver` for unauthenticated/test contexts.
    /// - A second consecutive 401 (the retried request also 401s) is not
    ///   retried again; it surfaces as `HTTPStatusError(statusCode: 401)`
    ///   from `validateSuccessStatus()`.
    ///
    /// - Parameters:
    ///   - request: The request to send. Any existing `Authorization` header
    ///     is overwritten when `tokenProvider` is non-nil.
    ///   - tokenProvider: Supplies the bearer token, and the force-fresh
    ///     token used for the 401 retry.
    /// - Returns: The response data and `URLResponse`, guaranteed to be a
    ///   2xx `HTTPURLResponse` (`validateSuccessStatus()` has already been
    ///   applied).
    /// - Throws: Whatever `data(for:)`, `tokenProvider`, or
    ///   `HTTPURLResponse.validateSuccessStatus()` throw.
    public func authedData(
        for request: URLRequest,
        tokenProvider: SessionTokenProvider?
    ) async throws -> (Data, URLResponse) {
        var authedRequest = request
        if let tokenProvider {
            let token = try await tokenProvider.token()
            authedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await self.data(for: authedRequest)

        guard let tokenProvider,
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 401 else {
            try (response as? HTTPURLResponse)?.validateSuccessStatus()
            return (responseData, response)
        }

        let freshToken = try await tokenProvider.reauthenticate()
        var retryRequest = request
        retryRequest.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")

        let (retryData, retryResponse) = try await self.data(for: retryRequest)
        try (retryResponse as? HTTPURLResponse)?.validateSuccessStatus()
        return (retryData, retryResponse)
    }
}
