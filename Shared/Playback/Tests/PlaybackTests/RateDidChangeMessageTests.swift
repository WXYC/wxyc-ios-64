//
//  RateDidChangeMessageTests.swift
//  Playback
//
//  Round-trip and post-and-observe tests for RateDidChangeMessage — the
//  typed wrapper around AVPlayer.rateDidChangeNotification shared by
//  RadioPlayerModule and HLSPlayerModule.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import AVFoundation
import Core
@testable import PlaybackCore

@Suite("RateDidChangeMessage", .serialized)
@MainActor
struct RateDidChangeMessageTests {

    @Test("makeNotification round-trips through makeMessage")
    func roundTrip() {
        let original = RateDidChangeMessage(rate: 0.75)
        let notification = RateDidChangeMessage.makeNotification(original, object: nil)
        let recovered = RateDidChangeMessage.makeMessage(notification)

        #expect(notification.name == AVPlayer.rateDidChangeNotification)
        #expect(notification.userInfo?["rate"] as? Float == 0.75)
        #expect(recovered?.rate == 0.75)
    }

    @Test("makeMessage reads the rate from an AVPlayer object, preferring it over userInfo")
    func makeMessageReadsRateFromPlayerObject() {
        // The live player is idle (no item), so its rate is 0 even though the
        // stray userInfo below claims 1.0 — the object-derived rate must win.
        let player = AVPlayer()
        let notification = Notification(
            name: AVPlayer.rateDidChangeNotification,
            object: player,
            userInfo: ["rate": Float(1.0)]
        )

        let message = RateDidChangeMessage.makeMessage(notification)

        #expect(message?.rate == player.rate)
        #expect(message?.rate == 0)
    }

    @Test("makeMessage reads the rate from userInfo when the object isn't an AVPlayer")
    func makeMessageReadsRateFromUserInfoForNonPlayerObject() {
        let notification = Notification(
            name: AVPlayer.rateDidChangeNotification,
            object: nil,
            userInfo: ["rate": Float(1.0)]
        )

        let message = RateDidChangeMessage.makeMessage(notification)

        #expect(message?.rate == 1.0)
    }

    @Test("makeMessage defaults to rate 0 when neither the object nor userInfo carry a rate")
    func makeMessageDefaultsToZero() {
        let notification = Notification(name: AVPlayer.rateDidChangeNotification, object: nil, userInfo: nil)

        let message = RateDidChangeMessage.makeMessage(notification)

        #expect(message?.rate == 0)
    }

    @Test("RateDidChangeMessage delivers through addMainActorObserver")
    func postAndObserve() async {
        let center = NotificationCenter()
        let expected = RateDidChangeMessage(rate: 1.0)
        let received = AsyncStream<RateDidChangeMessage>.makeStream()

        let token = center.addMainActorObserver(
            for: RateDidChangeMessage.self
        ) { message in
            received.continuation.yield(message)
            received.continuation.finish()
        }

        center.post(expected, subject: nil as AVPlayer?)

        var got: RateDidChangeMessage?
        for await message in received.stream {
            got = message
            break
        }

        #expect(got?.rate == 1.0)
        center.removeObserver(token)
    }

    // MARK: - Subject scoping
    //
    // One shared message type now backs both RadioPlayer and HLSPlayer, so the subject
    // passed to `addMainActorObserver(of:)` is the only thing separating two players'
    // rate changes. These two tests pin both halves of that contract. (This was already
    // true before #324 — both former types declared the same Notification.Name, so the
    // Swift type never discriminated delivery — but the merge makes it load-bearing in
    // a way that deserves a guard.)

    @Test("A subject-scoped observer receives only its own player's rate changes")
    func subjectScopedObserverIgnoresOtherPlayers() async throws {
        let center = NotificationCenter()
        let playerA = AVPlayer()
        let playerB = AVPlayer()
        let countA = Counter()
        let countB = Counter()

        let tokenA = center.addMainActorObserver(of: playerA, for: RateDidChangeMessage.self) { _ in
            countA.increment()
        }
        let tokenB = center.addMainActorObserver(of: playerB, for: RateDidChangeMessage.self) { _ in
            countB.increment()
        }
        defer {
            center.removeObserver(tokenA)
            center.removeObserver(tokenB)
        }

        center.post(RateDidChangeMessage(rate: 1.0), subject: playerA)
        center.post(RateDidChangeMessage(rate: 1.0), subject: playerA)
        try await Task.sleep(for: .milliseconds(100))

        #expect(countA.value == 2, "playerA's observer should see both of playerA's posts")
        #expect(countB.value == 0, "playerB's observer must not see playerA's rate changes")
    }

    @Test("A nil-subject observer receives rate changes from any player")
    func nilSubjectObserverReceivesEveryPlayer() async throws {
        // This is HLSPlayer's real production configuration: AVPlayerHLSAdapter wraps an
        // AVPlayer instead of subclassing it, so `player as? AVPlayer` is nil and the
        // observer registers unscoped.
        let center = NotificationCenter()
        let playerA = AVPlayer()
        let playerB = AVPlayer()
        let count = Counter()

        let token = center.addMainActorObserver(
            of: nil as AVPlayer?,
            for: RateDidChangeMessage.self
        ) { _ in
            count.increment()
        }
        defer { center.removeObserver(token) }

        center.post(RateDidChangeMessage(rate: 1.0), subject: playerA)
        center.post(RateDidChangeMessage(rate: 1.0), subject: playerB)
        try await Task.sleep(for: .milliseconds(100))

        #expect(count.value == 2, "an unscoped observer sees every player's rate change")
    }
}

// MARK: - Test Support

/// MainActor-confined tally, so the observer closures (which are `@MainActor`) can count
/// deliveries without a `nonisolated(unsafe)` var or a lock.
@MainActor
private final class Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
