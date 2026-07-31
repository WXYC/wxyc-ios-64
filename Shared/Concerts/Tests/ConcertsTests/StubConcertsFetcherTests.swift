//
//  StubConcertsFetcherTests.swift
//  ConcertsTests
//
//  Guards the error-shape fidelity of the shipped `ConcertsTesting` stub:
//  its unknown-id failure must be the same `HTTPStatusError` the concrete
//  `ConcertsFetcher` throws via `validateSuccessStatus()`, so consumers that
//  branch on the error type behave identically against stub and production.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Testing
import ConcertsTesting
@testable import Concerts

@Suite("StubConcertsFetcher")
struct StubConcertsFetcherTests {

    @Test("An unknown concert id throws the concrete fetcher's HTTPStatusError(404)")
    func unknownIdMirrorsProductionErrorShape() async throws {
        let stub = StubConcertsFetcher(pages: [])

        await #expect(throws: HTTPStatusError(statusCode: 404)) {
            _ = try await stub.fetchConcert(id: 999_999)
        }
    }
}
