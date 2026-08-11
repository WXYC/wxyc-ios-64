//
//  FailFastURLProtocolTests.swift
//  Core
//
//  Tests for CoreTesting's `FailFastURLProtocol` — promoted from Metadata's
//  `DiscogsAPIEntityResolverCachingTests.swift` (#786) so other packages
//  asserting "this code path must never touch the network" don't reinvent
//  it. Unlike `QueuedStubURLProtocol`, it carries no shared mutable state, so
//  this suite is deliberately NOT `.serialized` — that itself is the property
//  under test.
//
//  Created by Jake Bromberg on 08/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreTesting
import Foundation
import Testing

@Suite("FailFastURLProtocol")
struct FailFastURLProtocolTests {

    @Test("Every request fails immediately with .notConnectedToInternet")
    func requestFailsImmediately() async throws {
        let session = FailFastURLProtocol.makeSession()

        do {
            _ = try await session.data(from: URL(string: "https://example.invalid/never-reached")!)
            Issue.record("Expected the request to fail without reaching the network")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        }
    }

    @Test("Concurrent requests across independent sessions all fail without a shared-state race")
    func concurrentRequestsAllFailIndependently() async throws {
        // Proves the "needs no synchronization" claim in the type's header
        // doc: running several requests at once, with no `.serialized` trait
        // on this suite, must never crash, hang, or intermittently succeed.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let session = FailFastURLProtocol.makeSession()
                    do {
                        _ = try await session.data(from: URL(string: "https://example.invalid/never-reached")!)
                        Issue.record("Expected the request to fail")
                    } catch let error as URLError {
                        #expect(error.code == .notConnectedToInternet)
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
