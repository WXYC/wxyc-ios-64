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
        let service = WidgetStateService(
            playbackController: MockPlaybackController(),
            playlistService: makeTerminationTestPlaylistService(),
            relevanceUpdater: MockWidgetRelevanceUpdater()
        )
        _ = service  // retain so the termination observer stays registered

        // Simulate an active session persisted to the app-group defaults (init
        // clears it, so set it after construction), then let the OS post its
        // app-termination notification.
        UserDefaults.wxyc.set(true, forKey: "isPlaying")

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

        // Observer delivery is async on the main queue; poll until it lands.
        try await waitUntil { UserDefaults.wxyc.bool(forKey: "isPlaying") == false }
        #expect(UserDefaults.wxyc.bool(forKey: "isPlaying") == false)
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

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("timed out waiting for isPlaying to clear")
}

#endif
