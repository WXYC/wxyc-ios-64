//
//  ConcertSpotlightWindowObserverTests.swift
//  AppServices
//
//  Verifies the OT-C8 (WXYC/wxyc-ios-64#654) live caller that drives
//  `ConcertSpotlightDonationService.reconcile` from the On Tour window: a
//  loaded window is donated, the not-loaded-yet empty window is skipped, a
//  genuine shrink-to-zero after a real load is forwarded (so `reconcile` can
//  evict), and every non-empty window — including a byte-identical refresh — is
//  forwarded (dedup of unchanged windows is `reconcile`'s job, not the
//  observer's). Exercised over a recording reconciler spy so the assertions are
//  on exactly which windows/inputs reached `reconcile`, independent of
//  CoreSpotlight.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Concerts
import ConcertsTesting
import Foundation
import Testing
@testable import AppServices

@Suite("ConcertSpotlightWindowObserver")
struct ConcertSpotlightWindowObserverTests {

    @Test("donates a loaded window through the reconciler")
    func donatesLoadedWindow() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        let window = [Concert.stub(id: 1), Concert.stub(id: 2)]
        let didDonate = await observer.donate(window: window, reconciler: reconciler, inputs: .init())

        #expect(didDonate)
        let calls = await reconciler.calls
        #expect(calls.count == 1)
        #expect(calls.first?.window.map(\.id) == [1, 2])
    }

    @Test("skips the not-loaded-yet empty window (never evicts the whole index)")
    func skipsEmptyWindow() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        let didDonate = await observer.donate(window: [], reconciler: reconciler, inputs: .init())

        #expect(!didDonate)
        #expect(await reconciler.calls.isEmpty)
    }

    @Test("still donates once a window arrives after an initial empty emission")
    func donatesAfterEmptyThenLoaded() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        // Mirrors the launch sequence: Observations emits the initial empty
        // `allConcerts`, then the loaded window.
        await observer.donate(window: [], reconciler: reconciler, inputs: .init())
        await observer.donate(window: [Concert.stub(id: 7)], reconciler: reconciler, inputs: .init())

        #expect(await reconciler.calls.count == 1)
        #expect(await reconciler.calls.first?.window.map(\.id) == [7])
    }

    @Test("forwards a byte-identical refresh (dedup is reconcile's job, not the observer's)")
    func forwardsIdenticalRefresh() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        let window = [Concert.stub(id: 1, status: .onSale), Concert.stub(id: 2, status: .onSale)]
        await observer.donate(window: window, reconciler: reconciler, inputs: .init())
        // Same ids, same statuses — a pull-to-refresh that returned the same
        // data. The observer forwards it; `reconcile` no-ops internally against
        // its persisted snapshot. Mirroring that snapshot here would defeat
        // reconcile's advance-only-on-success retry, so the observer keeps no
        // window state of its own.
        let second = await observer.donate(window: window, reconciler: reconciler, inputs: .init())

        #expect(second)
        #expect(await reconciler.calls.count == 2)
    }

    @Test("forwards a genuine shrink-to-zero after a real load (so reconcile can evict)")
    func forwardsEmptyAfterDonation() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        await observer.donate(window: [Concert.stub(id: 1)], reconciler: reconciler, inputs: .init())
        // The curated window drained to empty *after* a real load — every show
        // passed or dropped. Unlike the not-loaded-yet empty window, this must
        // reach `reconcile` so the departed shows are evicted.
        let second = await observer.donate(window: [], reconciler: reconciler, inputs: .init())

        #expect(second)
        #expect(await reconciler.calls.count == 2)
        #expect(await reconciler.calls.last?.window.isEmpty == true)
    }

    @Test("re-reconciles when a still-present concert changes status (OT-C5 axis)")
    func reconcilesOnStatusChange() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        await observer.donate(window: [Concert.stub(id: 1, status: .onSale)], reconciler: reconciler, inputs: .init())
        // Same id, different status — must not be deduped away.
        let second = await observer.donate(window: [Concert.stub(id: 1, status: .soldOut)], reconciler: reconciler, inputs: .init())

        #expect(second)
        #expect(await reconciler.calls.count == 2)
    }

    @Test("re-reconciles when the set of concerts changes")
    func reconcilesOnMembershipChange() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        await observer.donate(window: [Concert.stub(id: 1)], reconciler: reconciler, inputs: .init())
        let second = await observer.donate(window: [Concert.stub(id: 1), Concert.stub(id: 2)], reconciler: reconciler, inputs: .init())

        #expect(second)
        #expect(await reconciler.calls.count == 2)
    }

    @Test("passes the on-device reconcile inputs straight through")
    func forwardsInputs() async {
        let reconciler = RecordingReconciler()
        let observer = ConcertSpotlightWindowObserver()

        let inputs = ConcertSpotlightReconcileInputs(
            likedArtists: [LikedArtist(id: 512, name: "Jessica Pratt")],
            stationCap: 5,
            dismissedConcertIDs: [99]
        )
        await observer.donate(window: [Concert.stub(id: 1)], reconciler: reconciler, inputs: inputs)

        let call = await reconciler.calls.first
        #expect(call?.likedArtists == [LikedArtist(id: 512, name: "Jessica Pratt")])
        #expect(call?.stationCap == 5)
        #expect(call?.dismissedConcertIDs == [99])
    }
}

/// Records each `reconcile` call's arguments so a test can assert exactly which
/// windows and inputs reached the donation service.
private actor RecordingReconciler: ConcertSpotlightReconciling {
    struct Call: Sendable {
        let window: [Concert]
        let likedArtists: [LikedArtist]
        let stationCap: Int
        let dismissedConcertIDs: Set<Int>
    }

    private(set) var calls: [Call] = []

    func reconcile(
        window: [Concert],
        likedArtists: [LikedArtist],
        stationCap: Int,
        dismissedConcertIDs: Set<Int>
    ) async {
        calls.append(Call(
            window: window,
            likedArtists: likedArtists,
            stationCap: stationCap,
            dismissedConcertIDs: dismissedConcertIDs
        ))
    }
}
#endif
