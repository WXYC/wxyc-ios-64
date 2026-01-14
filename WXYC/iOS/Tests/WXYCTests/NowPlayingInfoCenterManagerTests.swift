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
