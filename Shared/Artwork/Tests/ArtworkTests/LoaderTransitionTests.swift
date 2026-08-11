//
//  LoaderTransitionTests.swift
//  Artwork
//
//  Table-driven coverage of `LoaderTransition.apply`, the pure state machine
//  extracted from ArtworkLoader (#298). Every event is exercised as a
//  deterministic (state, event) -> (state, effects) mapping with no actor, no
//  clock, and no fake service — the async round trip through a real Task
//  stays in ArtworkLoaderTests.
//
//  Platform-agnostic (unlike ArtworkLoaderTests, which is UIKit-gated): this
//  is the whole point of extracting a pure function, so it runs on the
//  macOS host too.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
import PlaylistTesting
@testable import Artwork
@testable import Playlist
@testable import Core

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("LoaderTransition")
struct LoaderTransitionTests {

    // MARK: - load

    // `ArtworkLoader.State` isn't `Sendable` (its `.loaded` case carries a
    // `Core.Image`, itself not `Sendable`), so this narrow test-only shim
    // avoids widening `State`'s conformance in production code just to
    // satisfy `@Test(arguments:)`.
    //
    // What makes the `@unchecked` honest — swift-testing runs cases in
    // parallel, so "they run serially" would not be a justification:
    // every stored property is a `let`, nothing mutates a `LoadCase` after
    // construction, and no case below carries a `.loaded` payload, so no
    // reference-typed value crosses a task boundary at all. The instances
    // are read and never written.
    struct LoadCase: @unchecked Sendable {
        let description: String
        let existingState: ArtworkLoader.State?
        let expectedState: ArtworkLoader.State
        let expectsFetchEffect: Bool
    }

    static let loadCases: [LoadCase] = [
        LoadCase(
            description: "unloaded -> loading, starts a fetch",
            existingState: nil,
            expectedState: .loading,
            expectsFetchEffect: true
        ),
        LoadCase(
            description: "failed -> loading, starts a fetch (retry)",
            existingState: .failed,
            expectedState: .loading,
            expectsFetchEffect: true
        ),
        LoadCase(
            description: "loading -> loading, no-op (idempotent, no second fetch)",
            existingState: .loading,
            expectedState: .loading,
            expectsFetchEffect: false
        ),
    ]

    @Test("load transitions", arguments: loadCases)
    func loadTransitions(testCase: LoadCase) {
        let playcut = Playcut.stub(artistName: "Juana Molina")
        let key = playcut.artworkCacheKey
        var entries: [String: ArtworkLoader.Entry] = [:]
        if let existingState = testCase.existingState {
            entries[key] = ArtworkLoader.Entry(state: existingState, playcut: playcut)
        }

        let result = LoaderTransition.apply(.load(playcut), to: entries)

        #expect(result.next[key]?.state == testCase.expectedState, Comment(rawValue: testCase.description))
        #expect(
            result.effects == (testCase.expectsFetchEffect ? [.startFetch(playcut)] : []),
            Comment(rawValue: testCase.description)
        )
    }

    @Test("load on .loaded is a no-op — state and image untouched, no effect")
    func loadOnLoadedIsNoOp() {
        let playcut = Playcut.stub()
        let key = playcut.artworkCacheKey
        let loadedImage = CGImage.testImageWithColor(.red).toImage()
        let entries: [String: ArtworkLoader.Entry] = [
            key: ArtworkLoader.Entry(state: .loaded(loadedImage), playcut: playcut)
        ]

        let result = LoaderTransition.apply(.load(playcut), to: entries)

        #expect(result.next[key]?.state == .loaded(loadedImage))
        #expect(result.effects.isEmpty)
    }

    // MARK: - load / discogsUnavailable (#390)

    @Test("load short-circuits to .notOnDiscogs without a fetch effect when the MD flag is set")
    func loadShortCircuitsForDiscogsUnavailable() {
        let playcut = Playcut.stub(artistName: "flagged", discogsUnavailable: true, discogsUnavailableNote: "embargo")

        let result = LoaderTransition.apply(.load(playcut), to: [:])

        #expect(result.next[playcut.artworkCacheKey]?.state == .notOnDiscogs(note: "embargo"))
        #expect(result.effects.isEmpty)
    }

    @Test("load is a no-op when already .notOnDiscogs and still flagged")
    func loadIsNoOpWhenAlreadyNotOnDiscogs() {
        let playcut = Playcut.stub(artistName: "flagged", discogsUnavailable: true, discogsUnavailableNote: "embargo")
        let key = playcut.artworkCacheKey
        let entries: [String: ArtworkLoader.Entry] = [
            key: ArtworkLoader.Entry(state: .notOnDiscogs(note: "embargo"), playcut: playcut)
        ]

        let result = LoaderTransition.apply(.load(playcut), to: entries)

        #expect(result.next[key]?.state == .notOnDiscogs(note: "embargo"))
        #expect(result.effects.isEmpty)
    }

    @Test("load re-fetches once the discogsUnavailable flag clears (dj-site unflag restores artwork)")
    func loadRefetchesAfterFlagCleared() {
        let artistName = "flag-clears"
        let flagged = Playcut.stub(artistName: artistName, discogsUnavailable: true)
        let key = flagged.artworkCacheKey
        let entries: [String: ArtworkLoader.Entry] = [
            key: ArtworkLoader.Entry(state: .notOnDiscogs(note: nil), playcut: flagged)
        ]

        let unflagged = Playcut.stub(artistName: artistName, discogsUnavailable: nil)
        let result = LoaderTransition.apply(.load(unflagged), to: entries)

        #expect(result.next[key]?.state == .loading)
        #expect(result.effects == [.startFetch(unflagged)])
    }

    // MARK: - fetchSucceeded

    @Test("fetchSucceeded on a .loading entry transitions to .loaded")
    func fetchSucceededOnLoadingTransitionsToLoaded() {
        let playcut = Playcut.stub()
        let key = playcut.artworkCacheKey
        let entries: [String: ArtworkLoader.Entry] = [key: ArtworkLoader.Entry(state: .loading, playcut: playcut)]
        let image = CGImage.testImageWithColor(.red).toImage()

        let result = LoaderTransition.apply(.fetchSucceeded(key: key, image: image), to: entries)

        #expect(result.next[key]?.state == .loaded(image))
        #expect(result.effects.isEmpty)
    }

    @Test("fetchSucceeded for an absent key is a no-op (completed after a prune)")
    func fetchSucceededForAbsentKeyIsNoOp() {
        let image = CGImage.testImageWithColor(.blue).toImage()

        let result = LoaderTransition.apply(.fetchSucceeded(key: "gone", image: image), to: [:])

        #expect(result.next.isEmpty)
        #expect(result.effects.isEmpty)
    }

    @Test("fetchSucceeded for a key that is no longer .loading is a no-op (stale completion after reset/reload)")
    func fetchSucceededForNonLoadingKeyIsNoOp() {
        let playcut = Playcut.stub()
        let key = playcut.artworkCacheKey
        let currentImage = CGImage.testImageWithColor(.green).toImage()
        let entries: [String: ArtworkLoader.Entry] = [
            key: ArtworkLoader.Entry(state: .loaded(currentImage), playcut: playcut)
        ]
        let staleImage = CGImage.testImageWithColor(.red).toImage()

        let result = LoaderTransition.apply(.fetchSucceeded(key: key, image: staleImage), to: entries)

        #expect(result.next[key]?.state == .loaded(currentImage), "a late completion must not clobber a newer state")
    }

    @Test("fetchSucceeded must not clobber a .notOnDiscogs entry flagged while the fetch was in flight")
    func fetchSucceededOnNotOnDiscogsIsNoOp() {
        // The production-reachable case for the .loading guard: PlaylistView
        // re-`load`s every visible playcut on each poll, so a playcut whose MD
        // flag flips to discogsUnavailable while its fetch is in flight lands
        // on .notOnDiscogs before the fetch resolves. Writing .loaded here
        // would render artwork the #390 flag exists to suppress.
        let playcut = Playcut.stub(artistName: "flagged-mid-flight", discogsUnavailable: true, discogsUnavailableNote: "embargo")
        let key = playcut.artworkCacheKey
        let entries: [String: ArtworkLoader.Entry] = [
            key: ArtworkLoader.Entry(state: .notOnDiscogs(note: "embargo"), playcut: playcut)
        ]
        let inFlightResult = CGImage.testImageWithColor(.red).toImage()

        let result = LoaderTransition.apply(.fetchSucceeded(key: key, image: inFlightResult), to: entries)

        #expect(result.next[key]?.state == .notOnDiscogs(note: "embargo"), "a suppressed entry must not be resurrected by an in-flight fetch")
    }

    @Test("fetchSucceeded must not clobber a .failed entry left by a newer fetch")
    func fetchSucceededOnFailedIsNoOp() {
        let playcut = Playcut.stub(artistName: "stale-success")
        let key = playcut.artworkCacheKey
        let entries: [String: ArtworkLoader.Entry] = [
            key: ArtworkLoader.Entry(state: .failed, playcut: playcut)
        ]
        let staleImage = CGImage.testImageWithColor(.blue).toImage()

        let result = LoaderTransition.apply(.fetchSucceeded(key: key, image: staleImage), to: entries)

        // The next `load(_:)` retries a .failed entry, so nothing is lost
        // permanently — the newer fetch's verdict simply wins.
        #expect(result.next[key]?.state == .failed, "the newest fetch's outcome wins; a superseded success does not overwrite it")
    }

    // MARK: - fetchFailed

    @Test("fetchFailed on a .loading entry transitions to .failed")
    func fetchFailedOnLoadingTransitionsToFailed() {
        let playcut = Playcut.stub()
        let key = playcut.artworkCacheKey
        let entries: [String: ArtworkLoader.Entry] = [key: ArtworkLoader.Entry(state: .loading, playcut: playcut)]

        let result = LoaderTransition.apply(.fetchFailed(key: key), to: entries)

        #expect(result.next[key]?.state == .failed)
        #expect(result.effects.isEmpty)
    }

    @Test("fetchFailed for an absent key is a no-op (completed after a prune)")
    func fetchFailedForAbsentKeyIsNoOp() {
        let result = LoaderTransition.apply(.fetchFailed(key: "gone"), to: [:])

        #expect(result.next.isEmpty)
        #expect(result.effects.isEmpty)
    }

    @Test("fetchFailed for a key that is no longer .loading is a no-op")
    func fetchFailedForNonLoadingKeyIsNoOp() {
        let playcut = Playcut.stub()
        let key = playcut.artworkCacheKey
        let currentImage = CGImage.testImageWithColor(.green).toImage()
        let entries: [String: ArtworkLoader.Entry] = [
            key: ArtworkLoader.Entry(state: .loaded(currentImage), playcut: playcut)
        ]

        let result = LoaderTransition.apply(.fetchFailed(key: key), to: entries)

        #expect(result.next[key]?.state == .loaded(currentImage), "a stale failure must not clobber a newer state")
    }

    // MARK: - reset

    @Test("reset drops the entry for the given key")
    func resetDropsEntry() {
        let playcut = Playcut.stub()
        let key = playcut.artworkCacheKey
        let entries: [String: ArtworkLoader.Entry] = [key: ArtworkLoader.Entry(state: .loading, playcut: playcut)]

        let result = LoaderTransition.apply(.reset(key: key), to: entries)

        #expect(result.next[key] == nil)
        #expect(result.effects.isEmpty)
    }

    @Test("reset on an absent key is a no-op")
    func resetOnAbsentKeyIsNoOp() {
        let result = LoaderTransition.apply(.reset(key: "missing"), to: [:])

        #expect(result.next.isEmpty)
        #expect(result.effects.isEmpty)
    }

    // MARK: - retryFailures

    @Test("retryFailures re-issues load for every .failed entry and leaves everything else alone")
    func retryFailuresReissuesLoadForFailedEntries() {
        let failed1 = Playcut.stub(artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again")
        let failed2 = Playcut.stub(artistName: "Stereolab", releaseTitle: "Dots and Loops")
        let loaded = Playcut.stub(artistName: "Cat Power", releaseTitle: "Moon Pix")
        let unloaded = Playcut.stub(artistName: "Chuquimamani-Condori", releaseTitle: "Edits")
        let loadedImage = CGImage.testImageWithColor(.green).toImage()

        let entries: [String: ArtworkLoader.Entry] = [
            failed1.artworkCacheKey: ArtworkLoader.Entry(state: .failed, playcut: failed1),
            failed2.artworkCacheKey: ArtworkLoader.Entry(state: .failed, playcut: failed2),
            loaded.artworkCacheKey: ArtworkLoader.Entry(state: .loaded(loadedImage), playcut: loaded),
            unloaded.artworkCacheKey: ArtworkLoader.Entry(state: .unloaded, playcut: unloaded),
        ]

        let result = LoaderTransition.apply(.retryFailures, to: entries)

        #expect(result.next[failed1.artworkCacheKey]?.state == .loading)
        #expect(result.next[failed2.artworkCacheKey]?.state == .loading)
        #expect(result.next[loaded.artworkCacheKey]?.state == .loaded(loadedImage), "retryFailures must not touch .loaded entries")
        #expect(result.next[unloaded.artworkCacheKey]?.state == .unloaded, "retryFailures must not touch .unloaded entries")
        #expect(Set(result.effects) == Set([.startFetch(failed1), .startFetch(failed2)]))
    }

    @Test("retryFailures with no .failed entries is a no-op")
    func retryFailuresWithNoFailedEntriesIsNoOp() {
        let playcut = Playcut.stub()
        let image = CGImage.testImageWithColor(.blue).toImage()
        let entries: [String: ArtworkLoader.Entry] = [
            playcut.artworkCacheKey: ArtworkLoader.Entry(state: .loaded(image), playcut: playcut)
        ]

        let result = LoaderTransition.apply(.retryFailures, to: entries)

        #expect(result.next == entries)
        #expect(result.effects.isEmpty)
    }

    @Test("retryFailures does not touch .notOnDiscogs entries")
    func retryFailuresLeavesNotOnDiscogsAlone() {
        let playcut = Playcut.stub(artistName: "flagged", discogsUnavailable: true)
        let entries: [String: ArtworkLoader.Entry] = [
            playcut.artworkCacheKey: ArtworkLoader.Entry(state: .notOnDiscogs(note: nil), playcut: playcut)
        ]

        let result = LoaderTransition.apply(.retryFailures, to: entries)

        #expect(result.next == entries)
        #expect(result.effects.isEmpty)
    }

    // MARK: - prune

    @Test("prune drops entries not in the keep-set")
    func pruneDropsAbsentKeys() {
        let kept = Playcut.stub(artistName: "kept")
        let dropped = Playcut.stub(artistName: "dropped")
        let image = CGImage.testImageWithColor(.yellow).toImage()

        let entries: [String: ArtworkLoader.Entry] = [
            kept.artworkCacheKey: ArtworkLoader.Entry(state: .loaded(image), playcut: kept),
            dropped.artworkCacheKey: ArtworkLoader.Entry(state: .loaded(image), playcut: dropped),
        ]

        let result = LoaderTransition.apply(.prune(keepingKeys: [kept.artworkCacheKey]), to: entries)

        #expect(result.next[kept.artworkCacheKey] != nil)
        #expect(result.next[dropped.artworkCacheKey] == nil)
        #expect(result.effects.isEmpty)
    }

    @Test("prune with all keys kept is a no-op")
    func pruneWithAllKeysKeptIsNoOp() {
        let playcut = Playcut.stub()
        let image = CGImage.testImageWithColor(.orange).toImage()
        let entries: [String: ArtworkLoader.Entry] = [
            playcut.artworkCacheKey: ArtworkLoader.Entry(state: .loaded(image), playcut: playcut)
        ]

        let result = LoaderTransition.apply(.prune(keepingKeys: [playcut.artworkCacheKey]), to: entries)

        #expect(result.next == entries)
        #expect(result.effects.isEmpty)
    }
}
