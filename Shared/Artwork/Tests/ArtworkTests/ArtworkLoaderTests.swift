//
//  ArtworkLoaderTests.swift
//  Artwork
//
//  Tests for ArtworkLoader's per-playcut state machine, idempotency, retry-on-failure,
//  externally-driven invalidation, and pruning.
//
//  Created by Jake Bromberg on 05/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaylistTesting
@testable import Artwork
@testable import Playlist
@testable import Core

#if canImport(UIKit)
import UIKit

@MainActor
@Suite("ArtworkLoader Tests")
struct ArtworkLoaderTests {

    private func uniquePlaycut() -> Playcut {
        Playcut.stub(artistName: UUID().uuidString)
    }

    @Test("state(for:) returns .unloaded by default")
    func stateDefaultsToUnloaded() async throws {
        let service = MockArtworkService()
        let loader = ArtworkLoader(service: service)
        #expect(loader.state(for: uniquePlaycut()) == .unloaded)
    }

    @Test("load transitions unloaded -> loaded on success")
    func loadSucceeds() async throws {
        let service = MockArtworkService()
        service.artworkToReturn = CGImage.testImageWithColor(.red)

        let loader = ArtworkLoader(service: service)
        let playcut = uniquePlaycut()

        loader.load(playcut)
        try await waitForState(loader, of: playcut) { state in
            if case .loaded = state { true } else { false }
        }
        #expect(service.fetchCount == 1)
    }

    @Test("load transitions unloaded -> failed on error")
    func loadFails() async throws {
        let service = MockArtworkService()
        service.errorToThrow = ServiceError.noResults

        let loader = ArtworkLoader(service: service)
        let playcut = uniquePlaycut()

        loader.load(playcut)
        try await waitForState(loader, of: playcut) { $0 == .failed }
        #expect(service.fetchCount == 1)
    }

    @Test("load is a no-op when state is .loaded")
    func loadIsIdempotentWhenLoaded() async throws {
        let service = MockArtworkService()
        service.artworkToReturn = CGImage.testImageWithColor(.green)

        let loader = ArtworkLoader(service: service)
        let playcut = uniquePlaycut()

        loader.load(playcut)
        try await waitForState(loader, of: playcut) { state in
            if case .loaded = state { true } else { false }
        }
        #expect(service.fetchCount == 1)

        loader.load(playcut)
        loader.load(playcut)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.fetchCount == 1, "load() must not refetch when already loaded")
    }

    @Test("load is a no-op when state is .loading")
    func loadIsIdempotentWhileLoading() async throws {
        let service = MockArtworkService()
        service.artworkToReturn = CGImage.testImageWithColor(.blue)
        service.delaySeconds = 0.1

        let loader = ArtworkLoader(service: service)
        let playcut = uniquePlaycut()

        loader.load(playcut)
        loader.load(playcut)
        loader.load(playcut)
        try await waitForState(loader, of: playcut) { state in
            if case .loaded = state { true } else { false }
        }
        #expect(service.fetchCount == 1, "concurrent load() calls must coalesce")
    }

    @Test("load retries from .failed")
    func loadRetriesFromFailed() async throws {
        let service = MockArtworkService()
        service.errorToThrow = ServiceError.noResults

        let loader = ArtworkLoader(service: service)
        let playcut = uniquePlaycut()

        loader.load(playcut)
        try await waitForState(loader, of: playcut) { $0 == .failed }

        // Service starts succeeding.
        service.errorToThrow = nil
        service.artworkToReturn = CGImage.testImageWithColor(.purple)

        loader.load(playcut)
        try await waitForState(loader, of: playcut) { state in
            if case .loaded = state { true } else { false }
        }
        #expect(service.fetchCount == 2, "second load() after .failed must re-call the service")
    }

    @Test("reset(_:) drops .loaded entry so the next load re-fetches")
    func resetClearsLoadedEntry() async throws {
        let service = MockArtworkService()
        service.artworkToReturn = CGImage.testImageWithColor(.orange)

        let loader = ArtworkLoader(service: service)
        let playcut = uniquePlaycut()

        loader.load(playcut)
        try await waitForState(loader, of: playcut) { state in
            if case .loaded = state { true } else { false }
        }

        loader.reset(playcut)
        #expect(loader.state(for: playcut) == .unloaded)

        loader.load(playcut)
        try await waitForState(loader, of: playcut) { state in
            if case .loaded = state { true } else { false }
        }
        #expect(service.fetchCount == 2)
    }

    @Test("resetFailures only resets .failed entries")
    func resetFailuresOnlyTouchesFailed() async throws {
        let service = MockArtworkService()
        let loadedPlaycut = uniquePlaycut()
        let failedPlaycut = uniquePlaycut()

        let loader = ArtworkLoader(service: service)

        // Drive loadedPlaycut to .loaded.
        service.artworkToReturn = CGImage.testImageWithColor(.cyan)
        service.errorToThrow = nil
        loader.load(loadedPlaycut)
        try await waitForState(loader, of: loadedPlaycut) { state in
            if case .loaded = state { true } else { false }
        }

        // Drive failedPlaycut to .failed.
        service.artworkToReturn = nil
        service.errorToThrow = ServiceError.noResults
        loader.load(failedPlaycut)
        try await waitForState(loader, of: failedPlaycut) { $0 == .failed }

        loader.resetFailures()

        if case .loaded = loader.state(for: loadedPlaycut) {} else {
            Issue.record("resetFailures must not touch .loaded entries")
        }
        #expect(loader.state(for: failedPlaycut) == .unloaded)
    }

    @Test("prune drops entries whose keys are not in the keep-set")
    func pruneDropsAbsentKeys() async throws {
        let service = MockArtworkService()
        service.artworkToReturn = CGImage.testImageWithColor(.yellow)

        let loader = ArtworkLoader(service: service)
        let kept = uniquePlaycut()
        let dropped = uniquePlaycut()

        loader.load(kept)
        loader.load(dropped)
        try await waitForState(loader, of: kept) { state in
            if case .loaded = state { true } else { false }
        }
        try await waitForState(loader, of: dropped) { state in
            if case .loaded = state { true } else { false }
        }

        loader.prune(keepingKeys: [kept.artworkCacheKey])

        if case .loaded = loader.state(for: kept) {} else {
            Issue.record("kept playcut should retain its loaded state")
        }
        #expect(loader.state(for: dropped) == .unloaded)
    }
}

// MARK: - Test Helpers

/// Polls the loader on the main actor until `predicate(state)` is true or the
/// per-test timeout elapses. The helper exists because `load()` schedules a Task
/// internally and we need a deterministic way to await that task's completion
/// without exposing it through the public API.
@MainActor
private func waitForState(
    _ loader: ArtworkLoader,
    of playcut: Playcut,
    timeout: Duration = .seconds(2),
    matching predicate: (ArtworkLoader.State) -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if predicate(loader.state(for: playcut)) { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out waiting for loader state on \(playcut.artworkCacheKey); current state: \(loader.state(for: playcut))")
}

#endif
