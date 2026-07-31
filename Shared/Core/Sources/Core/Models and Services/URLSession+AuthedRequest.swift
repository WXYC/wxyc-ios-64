//
//  URLSession+AuthedRequest.swift
//  Core
//
//  Shared request seam for backend proxy endpoints that require the
//  anonymous-session bearer token: attaches the token, and on a 401 response
//  forces a fresh token via `SessionTokenProvider.reauthenticate(previousToken:)`
//  and retries the request exactly once. `Concerts.ConcertsFetcher` and the
//  `Metadata` package's proxy calls depend on `Core` but not on
//  `MusicShareKit` (the concrete `AuthenticationService`), so the retry
//  capability is expressed entirely through the `SessionTokenProvider`
//  protocol. Mirrors the reauthenticate-then-retry-once pattern in
//  `MusicShareKit.RequestService`, minus its bespoke 403 shadow-ban handling.
//  Passing the rejected token through lets a concurrency-safe conformer
//  coalesce a burst of concurrent 401s onto one fresh sign-in instead of
//  each caller racing its own.
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
    ///     is overwritten when `tokenProvider` is non-nil. The retry rebuilds
    ///     from this value, so use a `Data` body (`httpBody`) rather than a
    ///     one-shot `httpBodyStream`, which the first attempt would consume.
    ///   - tokenProvider: Supplies the bearer token, and the force-fresh
    ///     token used for the 401 retry.
    /// - Returns: The response data and `URLResponse`, guaranteed to be a
    ///   2xx `HTTPURLResponse` (`validateSuccessStatus()` has already been
    ///   applied; a non-HTTP response throws instead of escaping
    ///   unvalidated).
    /// - Throws: `URLError(.badServerResponse)` if the transport yields a
    ///   non-HTTP `URLResponse`; `CancellationError` if the caller is
    ///   cancelled before the retry is issued; otherwise whatever
    ///   `data(for:)`, `tokenProvider`, or
    ///   `HTTPURLResponse.validateSuccessStatus()` throw.
    public func authedData(
        for request: URLRequest,
        tokenProvider: SessionTokenProvider?
    ) async throws -> (Data, URLResponse) {
        var authedRequest = request
        var usedToken: String?
        if let tokenProvider {
            let token = try await tokenProvider.token()
            usedToken = token
            authedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await self.data(for: authedRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            // A non-HTTP response can't be status-validated; returning it
            // would silently break this method's 2xx guarantee (and a 401
            // delivered this way could never trigger the retry).
            throw URLError(.badServerResponse)
        }

        guard let tokenProvider, let usedToken, httpResponse.statusCode == 401 else {
            try httpResponse.validateSuccessStatus()
            return (responseData, response)
        }

        // Passing the exact token that got rejected lets the provider tell
        // "nobody has recovered from this yet" apart from "another
        // concurrent caller already did" — see `SessionTokenProvider`'s doc.
        let freshToken = try await tokenProvider.reauthenticate(previousToken: usedToken)

        // Reauthentication awaits a shared, non-cancellable refresh task —
        // the caller may have been cancelled (view teardown) while it was in
        // flight. Bail before paying for a retry nobody will read.
        try Task.checkCancellation()

        var retryRequest = request
        retryRequest.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")

        let (retryData, retryResponse) = try await self.data(for: retryRequest)
        guard let retryHTTPResponse = retryResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        try retryHTTPResponse.validateSuccessStatus()
        return (retryData, retryResponse)
    }
}
