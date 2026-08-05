//
//  PlaylistServiceWiringTests.swift
//  Playlist
//
//  Verifies PlaylistService derives its poll interval and SSE wiring from the
//  resolved PlaylistAPIVersion plus the caller's live-updates opt-in, instead
//  of picking them once at construction from arguments unrelated to the
//  version. Covers the reported enrichment-loss regression (v1 wiring in no
//  SSE source at all, so no push enrichment exists for a v1 poll to discard),
//  the (version, optedIn) derivation matrix — including the watchOS/tvOS
//  "stay poll-only under a forced v2" regression guard — and
//  switchAPIVersion(to:) tearing down and rebuilding the fetcher, interval,
//  and subscription together. See WXYC/wxyc-ios-64#749.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CoreTesting
import PlaylistTesting
@testable import Playlist
@testable import Caching

@MainActor
@Suite("PlaylistService wiring derivation", .serialized)
struct PlaylistServiceWiringTests {

    // MARK: - Enrichment-loss regression (the reported defect)

    @Test(
        "v1 wires in no SSE source even when the caller opted in, so no push enrichment exists for a v1 poll to discard",
        .timeLimit(.minutes(1))
    )
    func v1WiresInNoSSESourceEvenWhenOptedIn() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 1, chronOrderID: 1, songTitle: "Moon Pix", artistName: "Cat Power")
        ])
        // Scripted to look exactly like the enrichment a v2 push event would
        // carry. Under the reported defect (SSE wiring picked from arguments
        // unrelated to the resolved version) this connected on v1 and landed
        // on top of the v1 poll, whose unenriched payload then wholesale-
        // discarded it on the next tick. It must never be applied on v1.
        let enrichedUpdate = Playcut.stub(
            id: 1, chronOrderID: 1, songTitle: "Moon Pix", artistName: "Cat Power",
            metadataStatus: .enrichedMatch
        )
        let source = MockLiveFsEventSource(events: [.update(enrichedUpdate)])
        // A long interval on purpose: at a short one, a poll would wipe any
        // leaked enrichment before the assertion below sampled it, so the loop
        // would pass under the broken behavior too. Held open, a leak persists
        // and is observable.
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(),
            liveEventSource: source,
            apiVersion: .v1
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])

        // #749 lets AC #1 be satisfied two ways: no SSE source on v1, or a
        // merge that preserves enrichment. The fix takes the first, so pin
        // that explicitly — if someone later switches to the merge approach,
        // this assertion is the one that should be rewritten, not silently
        // reinterpreted.
        #expect(await service.wiringSnapshot().liveUpdatesActive == false)

        await service.setForegrounded(true)

        // The consume loop never starts, so the scripted enrichment never
        // reaches the playlist. With the interval held open above, a leak
        // would persist rather than being overwritten by a poll, so these
        // samples genuinely discriminate.
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(60))
            let snapshot = await service.currentPlaylistSnapshot()
            #expect(snapshot.playcuts.allSatisfy { $0.metadataStatus == nil })
        }

        #expect(source.connectCount == 0)
        #expect(await service.wiringSnapshot().hasLiveUpdatesTask == false)
    }

    // MARK: - Derivation matrix

    @Test(
        "interval and liveUpdatesActive are the conjunction of API-version support and caller opt-in",
        .timeLimit(.minutes(1)),
        arguments: apiVersionDerivationCases
    )
    func derivesIntervalAndLiveUpdatesActive(_ testCase: APIVersionDerivationCase) async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub()])
        let source: MockLiveFsEventSource? = testCase.optedIn ? MockLiveFsEventSource() : nil

        let service = PlaylistService(
            fetcher: fetcher,
            cacheCoordinator: makeTestCacheCoordinator(),
            liveEventSource: source,
            apiVersion: testCase.version
        )

        let snapshot = await service.wiringSnapshot()
        #expect(snapshot.apiVersion == testCase.version)
        #expect(snapshot.pollInterval == testCase.expectedInterval)
        #expect(snapshot.liveUpdatesActive == testCase.expectedLiveUpdatesActive)
    }

    // MARK: - switchAPIVersion tears down and rebuilds

    @Test(
        "switchAPIVersion tears down the old subscription before resetting state, and a later switch back starts a fresh one",
        .timeLimit(.minutes(1))
    )
    func switchAPIVersionTearsDownAndRebuilds() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        // finishesAfterScript: true so the consume loop reconnects with
        // backoff after draining the script — the mechanism that would leak
        // a stale-source event past the switch if the old task weren't
        // cancelled *and awaited* before state resets (see switchAPIVersion's
        // doc comment). An id far outside any real WXYC playcut id, so it can
        // never collide with whatever the post-switch live fetch returns.
        let staleInsert = Playcut.stub(
            id: 999_999, chronOrderID: 999_999, songTitle: "Aluminum Tunes", artistName: "Stereolab"
        )
        let source = MockLiveFsEventSource(events: [.insert(staleInsert)], finishesAfterScript: true)
        let service = PlaylistService(
            fetcher: fetcher,
            cacheCoordinator: makeTestCacheCoordinator(),
            liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        await service.setForegrounded(true)

        let afterInsert = await iterator.next()
        #expect(afterInsert?.playcuts.map(\.id).sorted() == [1, 999_999])

        let beforeSwitch = await service.wiringSnapshot()
        #expect(beforeSwitch.apiVersion == .v2)
        #expect(beforeSwitch.pollInterval == 300)
        #expect(beforeSwitch.liveUpdatesActive == true)

        let fetchesBeforeSwitch = fetcher.callCount
        await service.switchAPIVersion(to: .v1)

        // The switch's own reconciliation fetch went through the injected
        // double, not a rebuilt live-network `PlaylistFetcher`. Without this,
        // the test silently issues real requests to wxyc.info/api.wxyc.org and
        // its runtime becomes a function of network health — a 30 s per-request
        // timeout against this test's own 60 s limit.
        #expect(fetcher.callCount > fetchesBeforeSwitch)

        let afterSwitch = await service.wiringSnapshot()
        #expect(afterSwitch.apiVersion == .v1)
        #expect(afterSwitch.pollInterval == 30)
        #expect(afterSwitch.liveUpdatesActive == false)

        // Give the old source's reconnect-with-backoff loop (~1s cadence)
        // several cycles to prove it did NOT survive the switch: if it had,
        // its scripted insert would resurface id 999_999 in a later snapshot.
        // Deliberately NOT asserting on `connectCount` here — with a
        // finishing script `sawEvent` stays true, so an un-torn-down loop's
        // count keeps climbing on its own ~1s cadence independent of the
        // switch, making any specific-count assertion timing-shaped.
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(700))
            let snapshot = await service.currentPlaylistSnapshot()
            #expect(!snapshot.playcuts.map(\.id).contains(999_999))
        }

        // Switching back to v2 while still foregrounded starts a fresh
        // subscription — a "greater than" comparison against the pre-switch
        // count, not a specific literal, stays robust to any background
        // reconnect churn the (correctly torn down) old task can no longer
        // contribute.
        let connectCountBeforeReswitch = source.connectCount
        await service.switchAPIVersion(to: .v2)

        let afterReswitch = await service.wiringSnapshot()
        #expect(afterReswitch.apiVersion == .v2)
        #expect(afterReswitch.liveUpdatesActive == true)
        #expect(await waitUntil(timeout: .seconds(2)) { source.connectCount > connectCountBeforeReswitch })
    }

    // MARK: - switchAPIVersion reentrancy

    @Test(
        "a foreground toggle landing mid-switch cannot start a loop bound to the pre-switch source",
        .timeLimit(.minutes(1))
    )
    func foregroundToggleMidSwitchCannotStartStaleLoop() async throws {
        // Deterministic, with no sleeps and no wall-clock tolerance. The lever
        // is that `applyLiveEvent(.refetch)` routes to `fetchAndCachePlaylist()`
        // → `await fetcher.fetchPlaylist()`, and GatedPlaylistFetcher parks
        // there on a non-throwing continuation — which has no cancellation
        // handling. So the consume loop can be held at a point cancellation
        // cannot move it, and `switchAPIVersion`'s `await liveUpdatesTask?.value`
        // stays suspended for exactly as long as this test wants.
        let fetcher = GatedPlaylistFetcher(
            playlist: .stub(playcuts: [
                .stub(id: 3, chronOrderID: 3, songTitle: "Peng!", artistName: "Stereolab")
            ])
        )
        let source = MockLiveFsEventSource(events: [.refetch(source: "etl")])
        let service = PlaylistService(
            fetcher: fetcher,
            cacheCoordinator: makeTestCacheCoordinator(),
            liveEventSource: source,
            apiVersion: .v2
        )

        // No updates() subscriber on purpose: without one, startFetching()
        // never runs, so the gate sees only the consume loop's traffic.
        await service.setForegrounded(true)
        await fetcher.waitForEntry(count: 1)
        #expect(await service.wiringSnapshot().hasLiveUpdatesTask)

        // Parked. Start the switch — it cancels the consume loop (which cannot
        // observe the cancellation while parked) and suspends on its `.value`.
        let switchTask = Task { await service.switchAPIVersion(to: .v1) }

        // Wait for the switch to have actually latched before driving anything
        // at it. An unstructured Task's start is not ordered against the lines
        // below, so without this the toggles can win the race and the test
        // fails for the wrong reason. Each iteration is an actor hop plus a
        // yield — no sleeps, no wall-clock tolerance; the suite's .timeLimit
        // bounds it if the switch somehow never enters.
        while await service.wiringSnapshot().isSwitchingAPIVersion == false {
            await Task.yield()
        }

        // The exact reentrant pair from the orphan scenario. Both land while
        // the switch is suspended on `await cancelledLiveUpdates?.value`,
        // which cannot return until the gate is released below.
        await service.setForegrounded(false)
        await service.setForegrounded(true)

        // The load-bearing assertion. Without the isSwitchingAPIVersion latch,
        // that setForegrounded(true) passes every guard in
        // ensureLiveUpdatesRunning() — activeLiveEventSource is still the v2
        // source (not re-derived until after the await), isForegrounded is
        // true, liveUpdatesTask was just nil'd — and assigns a second loop
        // synchronously, bound to the source the switch is tearing down.
        #expect(await service.wiringSnapshot().hasLiveUpdatesTask == false)

        // Release generously rather than counting exactly: the gate
        // pre-authorizes, so surplus releases are inert, and a task parked on
        // a non-throwing continuation is uncancellable — meaning .timeLimit
        // cannot rescue an under-count. Releasing too few would hang the suite
        // instead of failing it, which is exactly what happens under the
        // regression this test guards (the orphaned loop parks on the gate
        // too, adding a third consumer).
        for _ in 0..<6 { fetcher.release() }
        await switchTask.value

        let afterSwitch = await service.wiringSnapshot()
        #expect(afterSwitch.apiVersion == .v1)
        #expect(afterSwitch.liveUpdatesActive == false)
        #expect(afterSwitch.pollInterval == 30)
        #expect(afterSwitch.hasLiveUpdatesTask == false)
    }

    // MARK: - Injected fetcher survives a version switch

    @Test(
        "switchAPIVersion keeps an injected fetcher instead of rebuilding a live-network one",
        .timeLimit(.minutes(1))
    )
    func switchAPIVersionPreservesInjectedFetcher() async throws {
        // `switchAPIVersion` used to hard-code `PlaylistFetcher(apiVersion:)`,
        // silently discarding any injected double — so every test that drove a
        // version switch issued real requests to wxyc.info / api.wxyc.org and
        // inherited their 30 s timeouts. The service now rebuilds through a
        // factory that returns the injected fetcher when there is one.
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 7, chronOrderID: 7, songTitle: "Ping Pong", artistName: "Stereolab")
        ])
        let service = PlaylistService(
            fetcher: fetcher,
            cacheCoordinator: makeTestCacheCoordinator(),
            liveEventSource: nil,
            apiVersion: .v1
        )

        _ = await service.currentPlaylistSnapshot()
        await service.switchAPIVersion(to: .v2)

        // The post-switch reconciliation fetch returned the double's playlist,
        // which no live endpoint would ever produce.
        let snapshot = await service.currentPlaylistSnapshot()
        #expect(snapshot.playcuts.map(\.id) == [7])
        #expect(await service.wiringSnapshot().apiVersion == .v2)
    }

    // MARK: - Production-shape pin (AC #5)

    @Test(
        "PlaylistService(apiVersion: .v2) with liveUpdatesEnabled left at its default stays poll-only",
        .timeLimit(.minutes(1))
    )
    func forcedV2StaysPollOnlyWithoutOptingIn() async throws {
        // The production-shaped public initializer, forcing v2 without
        // touching the shared UserDefaults.wxyc app-group override (which is
        // process-global and would make parallel suites order-dependent).
        // Pins that watchOS/tvOS/widgets/intents — none of which pass
        // `liveUpdatesEnabled: true` — stay poll-only now that
        // `PlaylistAPIVersion.defaultVersion` is `.v2`.
        //
        // "Production-shaped" here is about leaving `liveUpdatesEnabled` at
        // its default, not about the cache: the coordinator is still injected,
        // since the default is the real on-disk `MigratingDiskCache` and this
        // suite is only `.serialized` within itself.
        let service = PlaylistService(
            cacheCoordinator: makeTestCacheCoordinator(),
            apiVersion: .v2
        )

        let snapshot = await service.wiringSnapshot()
        #expect(snapshot.apiVersion == .v2)
        #expect(snapshot.liveUpdatesActive == false)
        #expect(snapshot.pollInterval == 30)
    }
}

// MARK: - Derivation matrix fixture

/// One row of the `(version, optedIn) -> (interval, liveUpdatesActive)`
/// derivation matrix. A named struct (rather than a raw tuple) so
/// `@Test(arguments:)` doesn't need to destructure a wide tuple — see the
/// repo's Swift Testing note about large tuple arrays blowing the
/// type-checker.
struct APIVersionDerivationCase: Sendable {
    let version: PlaylistAPIVersion
    let optedIn: Bool
    let expectedInterval: TimeInterval
    let expectedLiveUpdatesActive: Bool
}

/// Extracted to a top-level `let` with an explicit type annotation (per the
/// repo's Swift Testing tips) rather than inlined into `@Test(arguments:)`.
let apiVersionDerivationCases: [APIVersionDerivationCase] = [
    .init(version: .v1, optedIn: false, expectedInterval: 30, expectedLiveUpdatesActive: false),
    .init(version: .v1, optedIn: true, expectedInterval: 30, expectedLiveUpdatesActive: false),
    // Note: 30, NOT 300 — the watchOS/tvOS regression guard. A version alone
    // must never imply live updates; the caller has to opt in too.
    .init(version: .v2, optedIn: false, expectedInterval: 30, expectedLiveUpdatesActive: false),
    .init(version: .v2, optedIn: true, expectedInterval: 300, expectedLiveUpdatesActive: true),
]
