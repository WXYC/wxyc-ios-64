//
//  NowPlayingInfoCenterManagerTests.swift
//  WXYC
//
//  Unit tests for NowPlayingInfoCenterManager.
//  These tests verify that now playing info is correctly
//  propagated to MPNowPlayingInfoCenter.
//
//  Created by Jake Bromberg on 12/29/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import MediaPlayer
import UIKit
@testable import WXYC
@testable import Playlist
@testable import AppServices

// MARK: - Mock NowPlayingInfoCenter

/// Mock implementation of NowPlayingInfoCenterProtocol for testing.
@MainActor
final class MockNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {
    var nowPlayingInfo: [String: Any]?
    var playbackState: MPNowPlayingPlaybackState = .unknown
}

/// Spy that counts reads of the `nowPlayingInfo` getter.
///
/// Reading `MPNowPlayingInfoCenter.nowPlayingInfo` is a synchronous cross-process
/// (XPC) round-trip to `mediaserverd` that can block the main thread for seconds
/// under contention (Sentry IOS-3P AppHang). `NowPlayingInfoCenterManager` must
/// therefore never read the getter on the main thread; it compares against a local
/// cache instead. `storedInfo` exposes the last value written through the setter so
/// tests can assert on the result without inflating `getterReadCount`.
@MainActor
final class GetterCountingNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {
    private(set) var getterReadCount = 0
    private(set) var setterWriteCount = 0
    /// The last value written through the setter, readable without counting a getter read.
    private(set) var storedInfo: [String: Any]?

    var nowPlayingInfo: [String: Any]? {
        get {
            getterReadCount += 1
            return storedInfo
        }
        set {
            setterWriteCount += 1
            storedInfo = newValue
        }
    }

    var playbackState: MPNowPlayingPlaybackState = .unknown
}
    
// MARK: - Test Helpers

private func makePlaycut(
    id: UInt64 = 1,
    songTitle: String = "Test Song",
    artistName: String = "Test Artist",
    releaseTitle: String? = "Test Album"
) -> Playcut {
    Playcut(
        id: id,
        hour: 0,
        chronOrderID: id,
        timeCreated: 0,
        songTitle: songTitle,
        labelName: nil,
        artistName: artistName,
        releaseTitle: releaseTitle
    )
}

private func makeNowPlayingItem(
    id: UInt64 = 1,
    songTitle: String = "Test Song",
    artistName: String = "Test Artist",
    releaseTitle: String? = "Test Album",
    artwork: UIImage? = nil
) -> NowPlayingItem {
    NowPlayingItem(
        playcut: makePlaycut(
            id: id,
            songTitle: songTitle,
            artistName: artistName,
            releaseTitle: releaseTitle
        ),
        artwork: artwork
    )
}

// MARK: - Now Playing Info Tests

@Suite("Now Playing Info Updates")
@MainActor
struct NowPlayingInfoTests {

    @Test("Playcut info is set correctly")
    func playcutInfoSetCorrectly() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        let item = makeNowPlayingItem(
            songTitle: "My Song",
            artistName: "My Artist",
            releaseTitle: "My Album"
        )
        manager.handleNowPlayingItem(item)

        let info = mockInfoCenter.nowPlayingInfo
        #expect(info != nil)
        #expect(info?[MPMediaItemPropertyTitle] as? String == "My Song")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "My Artist")
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "My Album")
    }

    @Test("Artwork is set when provided")
    func artworkIsSetWhenProvided() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // Create a simple test image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let testImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }

        let item = makeNowPlayingItem(artwork: testImage)
        manager.handleNowPlayingItem(item)

        let info = mockInfoCenter.nowPlayingInfo
        #expect(info != nil)
        #expect(info?[MPMediaItemPropertyArtwork] != nil)
        #expect(info?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
    }

    @Test("Nil release title is stored as empty string")
    func nilReleaseTitleStoredAsEmptyString() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        let item = makeNowPlayingItem(releaseTitle: nil)
        manager.handleNowPlayingItem(item)

        let info = mockInfoCenter.nowPlayingInfo
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "")
    }

    @Test("Now playing info updates when new playcut arrives")
    func nowPlayingInfoUpdatesOnNewPlaycut() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        // First playcut
        let item1 = makeNowPlayingItem(songTitle: "Song 1", artistName: "Artist 1")
        manager.handleNowPlayingItem(item1)
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Song 1")

        // Second playcut
        let item2 = makeNowPlayingItem(songTitle: "Song 2", artistName: "Artist 2")
        manager.handleNowPlayingItem(item2)
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Song 2")
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtist] as? String == "Artist 2")
    }
}

// MARK: - Getter Avoidance Tests (IOS-3P)

/// Regression coverage for Sentry IOS-3P: an AppHang (>=2s, main thread) whose
/// culprit was `MPNowPlayingInfoCenter.nowPlayingInfo.getter` — a synchronous XPC
/// round-trip to `mediaserverd`. The manager must never read that getter on the
/// main thread; it compares against a locally cached copy of what it last set.
@Suite("Now Playing getter avoidance (IOS-3P)")
@MainActor
struct NowPlayingGetterAvoidanceTests {

    @Test("handleNowPlayingItem never reads the nowPlayingInfo getter but still sets info")
    func handleNowPlayingItemAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Song 1", artistName: "Artist 1"))

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPMediaItemPropertyTitle] as? String == "Song 1")
        #expect(spy.storedInfo?[MPMediaItemPropertyArtist] as? String == "Artist 1")
    }

    @Test("Repeated handleNowPlayingItem calls never read the getter")
    func repeatedHandleAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Song 1"))
        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Song 2"))

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPMediaItemPropertyTitle] as? String == "Song 2")
    }

    @Test("setPlaybackState never reads the getter")
    func setPlaybackStateAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.setPlaybackState(isPlaying: true)

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
    }

    @Test("updatePlaybackPosition never reads the getter")
    func updatePlaybackPositionAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.updatePlaybackPosition(secondsBehindLive: 30, maxLookback: 300)

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == false)
        #expect(spy.storedInfo?[MPMediaItemPropertyPlaybackDuration] as? Double == 300)
    }

    @Test("clearPlaybackPosition never reads the getter")
    func clearPlaybackPositionAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        // Establish some position first, then clear it.
        manager.updatePlaybackPosition(secondsBehindLive: 30, maxLookback: 300)
        manager.clearPlaybackPosition()

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(spy.storedInfo?[MPMediaItemPropertyPlaybackDuration] == nil)
    }
}

// MARK: - Playback State Tests

@Suite("Playback State Updates")
@MainActor
struct NowPlayingPlaybackStateTests {

    @Test(
        "setPlaybackState writes rate and state",
        arguments: [
            (isPlaying: true, expectedRate: 1.0, expectedState: MPNowPlayingPlaybackState.playing),
            (isPlaying: false, expectedRate: 0.0, expectedState: MPNowPlayingPlaybackState.paused),
        ]
    )
    func setPlaybackStateWritesRateAndState(
        isPlaying: Bool,
        expectedRate: Double,
        expectedState: MPNowPlayingPlaybackState
    ) {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.setPlaybackState(isPlaying: isPlaying)

        #expect(mockInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == expectedRate)
        #expect(mockInfoCenter.playbackState == expectedState)
    }

    @Test("Playback state survives subsequent track update")
    func playbackStateSurvivesTrackUpdate() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.setPlaybackState(isPlaying: true)
        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Next Song"))

        #expect(mockInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
        #expect(mockInfoCenter.playbackState == .playing)
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Next Song")
    }
}

// MARK: - Integration Tests

@Suite("Integration Tests")
@MainActor
struct NowPlayingIntegrationTests {

    @Test("BoundsSize is used for artwork")
    func boundsSizeUsedForArtwork() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let customBoundsSize = CGSize(width: 200, height: 200)

        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: customBoundsSize
        )

        let item = makeNowPlayingItem()
        manager.handleNowPlayingItem(item)

        guard let artwork = mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork else {
            Issue.record("Expected artwork to be set")
            return
        }

        #expect(artwork.bounds.size == customBoundsSize)
    }
}
