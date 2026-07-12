//
//  TicketFeatureCTAPersistenceTests.swift
//  Playlist
//
//  Tests the show/retire rules for the Box Office ticket discovery CTA: it
//  teaches the feature once and retires the moment the user opens a real
//  ticket, even if they never tapped the dismiss X.
//
//  Created by Jake Bromberg on 07/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Playlist

@Suite("TicketFeatureCTAPersistence")
@MainActor
struct TicketFeatureCTAPersistenceTests {

    /// A fresh persistence instance over an isolated UserDefaults suite so tests
    /// never see each other's writes.
    private func makePersistence() -> TicketFeatureCTAPersistence {
        let defaults = UserDefaults(suiteName: "TicketFeatureCTAPersistenceTests-\(UUID().uuidString)")!
        return TicketFeatureCTAPersistence(defaults: defaults)
    }

    // MARK: - Fresh install

    @Test("Shows on a fresh install")
    func showsInitially() {
        let persistence = makePersistence()

        #expect(persistence.shouldShow == true)
        #expect(persistence.hasSeenRealTicket == false)
        #expect(persistence.wasDismissed == false)
    }

    // MARK: - Dismiss

    @Test("Dismissing retires it for good")
    func dismissRetires() {
        let persistence = makePersistence()

        persistence.recordDismissed()

        #expect(persistence.wasDismissed == true)
        #expect(persistence.shouldShow == false)
    }

    // MARK: - Retire on real use

    @Test("Opening a real ticket retires it even without a dismiss")
    func realTicketRetiresWithoutDismiss() {
        let persistence = makePersistence()

        persistence.recordRealTicketSeen()

        #expect(persistence.hasSeenRealTicket == true)
        #expect(persistence.wasDismissed == false)
        #expect(persistence.shouldShow == false)
    }

    @Test("Recording a real-ticket view is idempotent")
    func realTicketSeenIdempotent() {
        let persistence = makePersistence()

        persistence.recordRealTicketSeen()
        persistence.recordRealTicketSeen()

        #expect(persistence.hasSeenRealTicket == true)
        #expect(persistence.shouldShow == false)
    }

    // MARK: - Reset

    @Test("Reset restores the fresh-install state")
    func resetRestoresInitialState() {
        let persistence = makePersistence()

        persistence.recordRealTicketSeen()
        persistence.recordDismissed()
        #expect(persistence.shouldShow == false)

        persistence.resetState()

        #expect(persistence.hasSeenRealTicket == false)
        #expect(persistence.wasDismissed == false)
        #expect(persistence.shouldShow == true)
    }
}
