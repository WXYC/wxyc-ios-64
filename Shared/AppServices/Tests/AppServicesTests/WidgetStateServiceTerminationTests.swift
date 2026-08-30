//
//  WidgetStateServiceTerminationTests.swift
//  AppServices
//
//  Tests that WidgetStateService clears the persisted isPlaying flag when the
//  OS posts its app-termination notification — on macOS (AppKit) as well as
//  iOS (UIKit), proving the platform-widened termination observer.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(WidgetKit)
import Foundation
import Caching
import PlaybackCore
import PlaylistTesting
import Testing
import WidgetKit
@testable import Playlist
@testable import AppServices

#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
@Suite("WidgetStateService Termination", .serialized, .timeLimit(.minutes(1)))
struct WidgetStateServiceTerminationTests {

    @Test("App-termination notification clears the persisted isPlaying flag")
    func terminationClearsIsPlaying() async throws {
        // `UserDefaults.wxyc` is a process-global app-group suite shared with
        // every other suite, and `.serialized` only orders tests within this
        // one — so snapshot the flag and restore it, leaving the shared store
        // exactly as it was found.
        let defaults = UserDefaults.wxyc
        let originalIsPlaying = defaults.object(forKey: "isPlaying")
        defer {
            if let originalIsPlaying {
                defaults.set(originalIsPlaying, forKey: "isPlaying")
            } else {
                defaults.removeObject(forKey: "isPlaying")
            }
        }

        let service = WidgetStateService(
            playbackController: MockPlaybackController(),
            playlistService: makeTerminationTestPlaylistService(),
            relevanceUpdater: MockWidgetRelevanceUpdater()
        )

        // Simulate an active session persisted to the app-group defaults (init
        // clears it, so set it after construction), then let the OS post its
        // app-termination notification.
        defaults.set(true, forKey: "isPlaying")

        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.post(
            name: UIApplication.willTerminateNotification,
            object: UIApplication.shared
        )
        #elseif canImport(AppKit)
        NotificationCenter.default.post(
            name: NSApplication.willTerminateNotification,
            object: NSApplication.shared
        )
        #endif

        // The service registers its observer with `queue: .main`, so the handler
        // is enqueued on `OperationQueue.main` rather than run synchronously by
        // `post`. Drain that serial queue deterministically instead of polling:
        // the handler sits ahead of our barrier in FIFO order, so it has cleared
        // the flag by the time this returns — no timeout, no flake.
        await drainMainQueue()

        #expect(defaults.bool(forKey: "isPlaying") == false)

        // The observer captures the service weakly, so the service has to be kept
        // alive across the post by this test. `_ = service` does not do that — it
        // is a discard, and ARC is free to release immediately after the last use.
        // Until the weak capture landed, this test passed only because the
        // observer's strong capture leaked every service into the process-global
        // `NotificationCenter`, which is the bug it now guards against.
        withExtendedLifetime(service) {}
    }

    @Test("Termination observer does not retain the service")
    func terminationObserverDoesNotRetainService() async throws {
        let defaults = UserDefaults.wxyc
        let originalIsPlaying = defaults.object(forKey: "isPlaying")
        defer {
            if let originalIsPlaying {
                defaults.set(originalIsPlaying, forKey: "isPlaying")
            } else {
                defaults.removeObject(forKey: "isPlaying")
            }
        }

        let relevanceUpdater = MockWidgetRelevanceUpdater()
        weak var weakService: WidgetStateService?

        do {
            let service = WidgetStateService(
                playbackController: MockPlaybackController(),
                playlistService: makeTerminationTestPlaylistService(),
                relevanceUpdater: relevanceUpdater
            )
            weakService = service

            // `init` spawns an unstructured Task that holds `service` strongly
            // until it completes. Wait for the single relevance call it makes,
            // so the only remaining reference is the local one going out of scope.
            await relevanceUpdater.waitForCallCount(1)
        }

        // Let the completed init Task drop its strong reference.
        await Task.yield()

        // `NotificationCenter.default` is process-global: a termination observer
        // that captures the service strongly keeps every instance ever built
        // alive for the life of the process, including one per test suite.
        #expect(weakService == nil)
    }
}

// MARK: - Helpers

@MainActor
private func makeTerminationTestPlaylistService() -> PlaylistService {
    PlaylistService(
        fetcher: MockPlaylistFetcher(),
        interval: 60,
        cacheCoordinator: CacheCoordinator(cache: InMemoryCache())
    )
}

/// Waits for work already enqueued on `OperationQueue.main` to finish. The main
/// queue is serial and FIFO, so a barrier operation appended after the post
/// resolves only once the `queue: .main` observer block ahead of it has run.
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        OperationQueue.main.addOperation {
            continuation.resume()
        }
    }
}

#endif
