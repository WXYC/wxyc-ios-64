//
//  FailFastURLProtocol.swift
//  CoreTesting
//
//  Promoted from Metadata's `DiscogsAPIEntityResolverCachingTests.swift`
//  (originally written for the cache-hit tests below) into CoreTesting by
//  #786, so other packages asserting "this code path must never touch the
//  network" don't reinvent it.
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// A `URLProtocol` that fails every request immediately, with no
/// configurable state.
///
/// Unlike `QueuedStubURLProtocol`, it needs no synchronization — there is
/// nothing to configure and nothing to race on, because its behavior never
/// varies — so it is safe to use from a suite that isn't `.serialized`, and
/// it never contends for `QueuedStubURLProtocol`'s one-adopter-per-bundle
/// slot (see that type's header doc). Reach for this one specifically when
/// several independent, concurrently-running tests each just need to prove
/// "no request was attempted" — `QueuedStubURLProtocol` would force them
/// into a single serialized suite for no benefit, since none of them need
/// configurable responses.
///
/// Use it to prove a cache-hit (or any other "must not reach the network")
/// path never issues a request: if the code under test regressed and
/// attempted a fetch, the request fails fast here instead of silently
/// succeeding, hanging, or reaching `URLSession.shared` in CI.
public final class FailFastURLProtocol: URLProtocol, @unchecked Sendable {
    override public class func canInit(with request: URLRequest) -> Bool { true }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override public func stopLoading() {}

    /// Creates an ephemeral `URLSession` whose traffic this protocol fails immediately.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailFastURLProtocol.self]
        return URLSession(configuration: config)
    }
}
