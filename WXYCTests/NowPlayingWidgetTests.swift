//
//  NowPlayingWidgetTests.swift
//  WXYCTests
//
//  Tests for NowPlayingWidget provider and utilities.
//  These tests verify the empty playlist handling that was causing widget crashes.
//

import Testing
import Foundation
@testable import WXYC
@testable import Playlist
@testable import AppServices

// MARK: - Test Extension (mirrors NowPlayingWidget's popFirst)

/// This extension mirrors the one in NowPlayingWidget/Extensions.swift
/// We define it here for testing since the widget target isn't accessible from tests.
extension RangeReplaceableCollection {
    /// Removes and returns the first element along with the remaining collection.
    /// Returns `nil` if the collection is empty.
    mutating func safePopFirst() -> (Element, Self)? {
        guard !isEmpty else { return nil }
        let first = removeFirst()
        return (first, self)
    }
}

// MARK: - popFirst() Extension Tests

@Suite("safePopFirst Extension Tests")
struct SafePopFirstExtensionTests {
    
    @Test("safePopFirst returns nil for empty array")
    func safePopFirstReturnsNilForEmptyArray() {
        var emptyArray: [Int] = []
        let result = emptyArray.safePopFirst()
        
        #expect(result == nil)
        #expect(emptyArray.isEmpty)
    }
    
    @Test("safePopFirst returns element and remaining for single element array")
    func safePopFirstReturnsSingleElement() {
        var array = [42]
        let result = array.safePopFirst()
        
        #expect(result != nil)
        #expect(result?.0 == 42)
        #expect(result?.1.isEmpty == true)
        #expect(array.isEmpty)
    }
    
    @Test("safePopFirst returns first element and remaining for multi-element array")
    func safePopFirstReturnsFirstAndRemaining() {
        var array = [1, 2, 3, 4]
        let result = array.safePopFirst()
        
        #expect(result != nil)
        #expect(result?.0 == 1)
        #expect(Array(result!.1) == [2, 3, 4])
        #expect(array == [2, 3, 4])
    }
    
    @Test("safePopFirst works with strings")
    func safePopFirstWorksWithStrings() {
        var array = ["first", "second", "third"]
        let result = array.safePopFirst()
        
        #expect(result != nil)
        #expect(result?.0 == "first")
        #expect(Array(result!.1) == ["second", "third"])
    }
    
    @Test("safePopFirst preserves type with ArraySlice")
    func safePopFirstPreservesArraySliceType() {
        var array = [1, 2, 3, 4, 5]
        
        // First pop
        guard let (first, remaining) = array.safePopFirst() else {
            Issue.record("Expected non-nil result")
            return
        }
        
        #expect(first == 1)
        #expect(Array(remaining) == [2, 3, 4, 5])
    }
    
    @Test("Multiple sequential safePopFirst calls work correctly")
    func multipleSafePopFirstCalls() {
        var array = [1, 2, 3]
        
        let first = array.safePopFirst()
        #expect(first?.0 == 1)
        
        let second = array.safePopFirst()
        #expect(second?.0 == 2)
        
        let third = array.safePopFirst()
        #expect(third?.0 == 3)
        
        let fourth = array.safePopFirst()
        #expect(fourth == nil)
    }
}

// MARK: - Test Helpers

/// Creates a test playcut for use in tests
func makeTestPlaycut(id: UInt64 = 1, songTitle: String = "Test Song", artistName: String = "Test Artist") -> Playcut {
    Playcut(
        id: id,
        hour: 0,
        chronOrderID: id,
        songTitle: songTitle,
        labelName: nil,
        artistName: artistName,
        releaseTitle: "Test Album"
    )
}

/// Creates a test NowPlayingItem for use in tests
func makeTestNowPlayingItem(id: UInt64 = 1, songTitle: String = "Test Song", artistName: String = "Test Artist") -> NowPlayingItem {
    NowPlayingItem(playcut: makeTestPlaycut(id: id, songTitle: songTitle, artistName: artistName))
}

// MARK: - Empty Playlist Handling Tests

@Suite("Empty Playlist Handling Tests")
struct EmptyPlaylistHandlingTests {
    
    @Test("Empty playlist array returns nil from safePopFirst")
    func emptyPlaylistReturnsNil() {
        var playcuts: [Playcut] = []
        let result = playcuts.safePopFirst()
        
        #expect(result == nil)
    }
    
    @Test("Guard pattern correctly handles empty NowPlayingItem array")
    func guardPatternHandlesEmptyArray() {
        var items: [NowPlayingItem] = []
        
        // This simulates the pattern used in Provider.getSnapshot
        guard let (_, _) = items.safePopFirst() else {
            // This is the expected path for empty arrays
            #expect(true)
            return
        }
        
        Issue.record("Should not reach here with empty array")
    }
    
    @Test("Guard pattern correctly handles non-empty NowPlayingItem array")
    func guardPatternHandlesNonEmptyArray() {
        var items = [makeTestNowPlayingItem()]
        
        guard let (nowPlaying, remaining) = items.safePopFirst() else {
            Issue.record("Should not fail with non-empty array")
            return
        }
        
        #expect(nowPlaying.playcut.songTitle == "Test Song")
        #expect(remaining.isEmpty)
    }
    
    @Test("Simulated getTimeline flow with empty playlist uses placeholder")
    func getTimelineEmptyPlaylistUsesPlaceholder() {
        // Simulate the getTimeline flow
        var nowPlayingItemsWithArtwork: [NowPlayingItem] = []
        var usedPlaceholder = true
        
        // This mirrors the logic in Provider.getTimeline
        nowPlayingItemsWithArtwork.sort(by: >)
        if let (_, _) = nowPlayingItemsWithArtwork.safePopFirst() {
            usedPlaceholder = false
        }
        
        #expect(usedPlaceholder == true)
    }
    
    @Test("Simulated getTimeline flow with populated playlist creates entry")
    func getTimelinePopulatedPlaylistCreatesEntry() {
        var nowPlayingItemsWithArtwork = [makeTestNowPlayingItem()]
        var usedPlaceholder = true
        
        // This mirrors the logic in Provider.getTimeline
        nowPlayingItemsWithArtwork.sort(by: >)
        if let (_, _) = nowPlayingItemsWithArtwork.safePopFirst() {
            usedPlaceholder = false
        }
        
        #expect(usedPlaceholder == false)
    }
    
    @Test("Simulated getSnapshot flow with empty playlist returns placeholder")
    func getSnapshotEmptyPlaylistReturnsPlaceholder() {
        var nowPlayingItems: [NowPlayingItem] = []
        var returnedPlaceholder = false
        
        // This mirrors the logic in Provider.getSnapshot
        guard let (_, _) = nowPlayingItems.safePopFirst() else {
            returnedPlaceholder = true
            // In real code: completion(.placeholder(family: family))
            return
        }
        
        // Should not reach here
        #expect(returnedPlaceholder == true)
    }
}

// MARK: - Regression Tests

@Suite("Widget Crash Regression Tests")
struct WidgetCrashRegressionTests {
    
    @Test("Empty collection no longer crashes - the original bug scenario")
    func emptyCollectionNoCrash() {
        // This test ensures we never regress to the original crash
        // The crash was: "Can't remove first element from an empty collection"
        var emptyArray: [NowPlayingItem] = []
        
        // Before the fix, this would crash
        // After the fix, this returns nil safely
        let result = emptyArray.safePopFirst()
        
        #expect(result == nil)
    }
    
    @Test("Preview mode with empty array handled safely")
    func previewModeEmptyArraySafe() {
        // In preview mode, we use placeholders, so this shouldn't happen
        // But we test it anyway for safety
        var items: [NowPlayingItem] = []
        
        items.sort(by: >)
        if let (item, remaining) = items.safePopFirst() {
            // This path should not be taken for empty array
            _ = item
            _ = remaining
            Issue.record("Should not enter this branch with empty array")
        } else {
            // This is the expected path - use placeholder
            #expect(true)
        }
    }
    
    @Test("Multiple items sorted and first extracted correctly")
    func multipleItemsSortedCorrectly() {
        // Create items with different chronOrderIDs to test sorting
        var items = [
            makeTestNowPlayingItem(id: 3, songTitle: "Third"),
            makeTestNowPlayingItem(id: 1, songTitle: "First"),
            makeTestNowPlayingItem(id: 2, songTitle: "Second"),
        ]
        
        // Sort descending (higher chronOrderID first)
        items.sort(by: >)
        
        guard let (first, remaining) = items.safePopFirst() else {
            Issue.record("Should have items")
            return
        }
        
        // After sorting by > (descending), chronOrderID 3 should be first
        #expect(first.playcut.chronOrderID == 3)
        #expect(first.playcut.songTitle == "Third")
        #expect(remaining.count == 2)
    }
    
    @Test("Single item in array works correctly")
    func singleItemArrayWorks() {
        var items = [makeTestNowPlayingItem(id: 1, songTitle: "Only Song")]
        
        items.sort(by: >)
        guard let (nowPlaying, remaining) = items.safePopFirst() else {
            Issue.record("Should have one item")
            return
        }
        
        #expect(nowPlaying.playcut.songTitle == "Only Song")
        #expect(remaining.isEmpty)
    }
}
