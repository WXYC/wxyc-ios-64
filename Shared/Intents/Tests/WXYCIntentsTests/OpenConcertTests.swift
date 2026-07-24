//
//  OpenConcertTests.swift
//  WXYCIntents
//
//  Verifies OpenConcert.perform() posts a ConcertOpenMessage carrying the
//  target entity's backend id with source .scheme — the same
//  ConcertOpenMessage the universal-link/scheme handler already posts, so
//  the existing Singletonia -> PendingConcertLink -> OnTourTabView.resolveConcert
//  ladder opens the poster detail with no new routing (#537).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Concerts
import ConcertsTesting
@testable import WXYCIntents

@Suite("OpenConcert")
struct OpenConcertTests {
    @Test("perform() posts a ConcertOpenMessage with the target's id and .scheme source")
    @MainActor
    func performPostsConcertOpenMessage() async throws {
        let entity = try #require(ConcertEntity(concert: .stub(id: 4821)))
        let intent = OpenConcert(target: entity)

        // `queue: nil` delivers the observer synchronously on the poster's
        // thread, so the round-trip is race-free without polling — the same
        // pattern ConcertOpenMessageTests uses against a scoped center. This
        // test necessarily posts through the shared `NotificationCenter.default`,
        // because that's what `perform()` uses (mirroring OpenPlaycut); the
        // message name is unique enough that no other suite posts it, and the
        // observer is torn down before this test returns. `perform()` runs on
        // a detached Task because the continuation closure below is
        // synchronous and can't itself `await`.
        var observer: NSObjectProtocol?
        let received: ConcertOpenMessage = await withCheckedContinuation { continuation in
            observer = NotificationCenter.default.addObserver(
                forName: ConcertOpenMessage.name,
                object: nil,
                queue: nil
            ) { notification in
                if let message = ConcertOpenMessage.makeMessage(notification) {
                    continuation.resume(returning: message)
                }
            }
            Task {
                _ = try? await intent.perform()
            }
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        #expect(received.concertID == 4821)
        #expect(received.source == .scheme)
    }
}
