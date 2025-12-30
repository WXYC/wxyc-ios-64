//
//  NowPlayingInfoCenterManagerTests.swift
//  WXYCTests
//
//  Unit tests for NowPlayingInfoCenterManager.
//  These tests verify that now playing info and playback state
//  are correctly propagated to MPNowPlayingInfoCenter.
//

import Testing
import Foundation
import MediaPlayer
import UIKit
@testable import WXYC
@testable import Playlist
@testable import AppServices
@testable import Core

// MARK: - Mock NowPlayingInfoCenter

/// Mock implementation of NowPlayingInfoCenterProtocol for testing.
@MainActor
final class MockNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {
    var playbackState: MPNowPlayingPlaybackState = .unknown
    var nowPlayingInfo: [String: Any]?
    
    var playbackStateChanges: [MPNowPlayingPlaybackState] = []
    var nowPlayingInfoUpdates: [[String: Any]] = []
    
    func reset() {
        playbackState = .unknown
        nowPlayingInfo = nil
        playbackStateChanges = []
        nowPlayingInfoUpdates = []
    }
}

// MARK: - Mock NowPlayingItem Stream

/// Mock AsyncSequence that yields NowPlayingItems on demand.
struct MockNowPlayingItemStream: AsyncSequence, Sendable {
    typealias Element = NowPlayingItem
    
    private let stream: AsyncStream<NowPlayingItem>
    let continuation: AsyncStream<NowPlayingItem>.Continuation
    
    init() {
        var capturedContinuation: AsyncStream<NowPlayingItem>.Continuation!
        self.stream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }
    
    nonisolated func makeAsyncIterator() -> AsyncStream<NowPlayingItem>.Iterator {
        stream.makeAsyncIterator()
    }
    
    func yield(_ item: NowPlayingItem) {
        continuation.yield(item)
    }
    
    func finish() {
        continuation.finish()
    }
}

// MARK: - Mock Playback State Stream

/// A simple async stream for testing playback state changes.
struct MockPlaybackStateStream: AsyncSequence, Sendable {
    typealias Element = Bool
    
    private let stream: AsyncStream<Bool>
    let continuation: AsyncStream<Bool>.Continuation
    
    init() {
        var capturedContinuation: AsyncStream<Bool>.Continuation!
        self.stream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }
    
    nonisolated func makeAsyncIterator() -> AsyncStream<Bool>.Iterator {
        stream.makeAsyncIterator()
    }
    
    func yield(_ isPlaying: Bool) {
        continuation.yield(isPlaying)
    }
    
    func finish() {
        continuation.finish()
    }
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

// MARK: - Playback State Tests

@Suite("Playback State Updates")
@MainActor
struct PlaybackStateTests {
    
    @Test("Playback state is set to playing when isPlaying becomes true")
    func playbackStateSetToPlaying() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // Yield playing state
        playbackStream.yield(true)
        
        // Give the async task time to process
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(mockInfoCenter.playbackState == .playing)
    }
    
    @Test("Playback state is set to paused when isPlaying becomes false")
    func playbackStateSetToPaused() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // Yield paused state
        playbackStream.yield(false)
        
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(mockInfoCenter.playbackState == .paused)
    }
    
    @Test("Playback state updates correctly through multiple transitions")
    func playbackStateMultipleTransitions() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // Transition: stopped -> playing
        playbackStream.yield(true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockInfoCenter.playbackState == .playing)
        
        // Transition: playing -> paused
        playbackStream.yield(false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockInfoCenter.playbackState == .paused)
        
        // Transition: paused -> playing
        playbackStream.yield(true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockInfoCenter.playbackState == .playing)
    }
}

// MARK: - Now Playing Info Tests

@Suite("Now Playing Info Updates")
@MainActor
struct NowPlayingInfoTests {
    
    @Test("Playcut info is set correctly")
    func playcutInfoSetCorrectly() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // Yield a now playing item
        let item = makeNowPlayingItem(
            songTitle: "My Song",
            artistName: "My Artist",
            releaseTitle: "My Album"
        )
        nowPlayingStream.yield(item)
        
        try await Task.sleep(for: .milliseconds(50))
        
        let info = mockInfoCenter.nowPlayingInfo
        #expect(info != nil)
        #expect(info?[MPMediaItemPropertyTitle] as? String == "My Song")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "My Artist")
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "My Album")
    }
    
    @Test("Artwork is set when provided")
    func artworkIsSetWhenProvided() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
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
        nowPlayingStream.yield(item)
        
        try await Task.sleep(for: .milliseconds(50))
        
        let info = mockInfoCenter.nowPlayingInfo
        #expect(info != nil)
        #expect(info?[MPMediaItemPropertyArtwork] != nil)
        #expect(info?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
    }
    
    @Test("Nil release title is stored as empty string")
    func nilReleaseTitleStoredAsEmptyString() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        let item = makeNowPlayingItem(releaseTitle: nil)
        nowPlayingStream.yield(item)
        
        try await Task.sleep(for: .milliseconds(50))
        
        let info = mockInfoCenter.nowPlayingInfo
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "")
    }
    
    @Test("Now playing info updates when new playcut arrives")
    func nowPlayingInfoUpdatesOnNewPlaycut() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // First playcut
        let item1 = makeNowPlayingItem(songTitle: "Song 1", artistName: "Artist 1")
        nowPlayingStream.yield(item1)
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Song 1")
        
        // Second playcut
        let item2 = makeNowPlayingItem(songTitle: "Song 2", artistName: "Artist 2")
        nowPlayingStream.yield(item2)
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Song 2")
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtist] as? String == "Artist 2")
    }
}

// MARK: - Integration Tests

@Suite("Integration Tests")
@MainActor
struct NowPlayingIntegrationTests {
    
    @Test("Playcut and playback state can update independently")
    func playcutAndPlaybackStateIndependent() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // Update playback state first
        playbackStream.yield(true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockInfoCenter.playbackState == .playing)
        #expect(mockInfoCenter.nowPlayingInfo == nil || mockInfoCenter.nowPlayingInfo?.isEmpty == true)
        
        // Now update playcut
        let item = makeNowPlayingItem(songTitle: "Test Song")
        nowPlayingStream.yield(item)
        try await Task.sleep(for: .milliseconds(50))
        
        // Both should now be set
        #expect(mockInfoCenter.playbackState == .playing)
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Test Song")
    }
    
    @Test("BoundsSize is used for artwork")
    func boundsSizeUsedForArtwork() async throws {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let playbackStream = MockPlaybackStateStream()
        let nowPlayingStream = MockNowPlayingItemStream()
        
        let customBoundsSize = CGSize(width: 200, height: 200)
        
        let _ = NowPlayingInfoCenterManager(
            nowPlayingItemStream: nowPlayingStream,
            playbackStateStream: playbackStream,
            infoCenter: mockInfoCenter,
            boundsSize: customBoundsSize
        )
        
        let item = makeNowPlayingItem()
        nowPlayingStream.yield(item)
        try await Task.sleep(for: .milliseconds(50))
        
        guard let artwork = mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork else {
            Issue.record("Expected artwork to be set")
            return
        }
        
        #expect(artwork.bounds.size == customBoundsSize)
    }
}

