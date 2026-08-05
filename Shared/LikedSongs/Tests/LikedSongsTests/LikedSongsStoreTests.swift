//
//  LikedSongsStoreTests.swift
//  LikedSongs
//
//  Store behavior: toggle/dedupe across release and casing variants, newest-
//  first ordering, observation-time id healing, the For You id projection,
//  analytics bucketing, and persistence (write-through, round-trip, corrupt-
//  data recovery) — all through InMemoryFileStorage so the real encode/decode
//  paths run with no disk.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import CoreTesting
import PlaylistTesting
@testable import LikedSongs

/// Injectable clock: tests advance it to control `likedAt` ordering.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _date = Date(timeIntervalSince1970: 1_000)
    var date: Date {
        lock.lock(); defer { lock.unlock() }
        return _date
    }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _date += seconds
    }
}

@MainActor
@Suite("LikedSongsStore Tests")
struct LikedSongsStoreTests {

    private func makeStore(
        storage: InMemoryFileStorage = InMemoryFileStorage()
    ) -> (LikedSongsStore, InMemoryFileStorage, TestClock) {
        let clock = TestClock()
        let store = LikedSongsStore(storage: storage, now: { clock.date })
        return (store, storage, clock)
    }

    // MARK: - Toggle + dedupe

    @Test("Liking inserts a snapshot of the playcut with the clock's timestamp")
    func likeInserts() {
        let (store, storage, clock) = makeStore()
        let liked = store.toggle(Playcut.stub(
            songTitle: "Back, Baby", labelName: "Drag City",
            artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again",
            artworkURL: URL(string: "https://example.org/oyola.jpg"), artistId: 812
        ))
        #expect(liked == true)
        #expect(store.songs.count == 1)
        let song = store.songs[0]
        #expect(song.songTitle == "Back, Baby")
        #expect(song.artistName == "Jessica Pratt")
        #expect(song.artistId == 812)
        #expect(song.releaseTitle == "On Your Own Love Again")
        #expect(song.labelName == "Drag City")
        #expect(song.artworkURL?.absoluteString == "https://example.org/oyola.jpg")
        #expect(song.likedAt == clock.date)
        #expect(storage.saveCount == 1)
        #expect(store.isLiked(artistName: "Jessica Pratt", songTitle: "Back, Baby"))
    }

    @Test("Toggling the same song again removes it")
    func toggleRemoves() {
        let (store, storage, _) = makeStore()
        store.toggle(Playcut.stub(songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: nil))
        let liked = store.toggle(Playcut.stub(songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: nil))
        #expect(liked == false)
        #expect(store.songs.isEmpty)
        #expect(storage.saveCount == 2)
    }

    @Test("The same song across releases, casing, and linkage is one liked song")
    func dedupesAcrossVariants() {
        let (store, _, _) = makeStore()
        store.toggle(Playcut.stub(
            songTitle: "Call Your Name", artistName: "Chuquimamani-Condori",
            releaseTitle: "Edits", artistId: 977
        ))
        // Free-text ALL-CAPS replay of the same song, different (absent) album:
        // same folded identity, so this toggle unlikes the existing row.
        let liked = store.toggle(Playcut.stub(songTitle: "CALL YOUR NAME", artistName: "CHUQUIMAMANI-CONDORI", releaseTitle: nil))
        #expect(liked == false)
        #expect(store.songs.isEmpty)
    }

    @Test("isLiked matches across casing and diacritics")
    func isLikedFolds() {
        let (store, _, _) = makeStore()
        store.toggle(Playcut.stub(songTitle: "Midnight Sun", artistName: "Nilüfer Yanya", releaseTitle: nil))
        #expect(store.isLiked(artistName: "NILUFER  YANYA", songTitle: "midnight sun"))
        #expect(!store.isLiked(artistName: "Nilüfer Yanya", songTitle: "Anotherlife"))
    }

    @Test("Songs sort newest first")
    func newestFirst() {
        let (store, _, clock) = makeStore()
        store.toggle(Playcut.stub(songTitle: "Metronomic Underground", artistName: "Stereolab", releaseTitle: nil))
        clock.advance(60)
        store.toggle(Playcut.stub(songTitle: "In a Sentimental Mood", artistName: "Duke Ellington & John Coltrane", releaseTitle: nil))
        #expect(store.songs.map(\.songTitle) == ["In a Sentimental Mood", "Metronomic Underground"])
    }

    @Test("unlike(snapshot) removes the row — the Liked tab's swipe path")
    func unlikeSnapshot() {
        let (store, _, _) = makeStore()
        store.toggle(Playcut.stub(songTitle: "Cross Bones Style", artistName: "Cat Power", releaseTitle: nil))
        store.unlike(store.songs[0])
        #expect(store.songs.isEmpty)
        #expect(!store.isLiked(artistName: "Cat Power", songTitle: "Cross Bones Style"))
    }

    // MARK: - Healing

    @Test("Heal stamps the observed artist id onto folded-name matches, preserving likedAt")
    func healStamps() {
        let (store, _, clock) = makeStore()
        store.toggle(Playcut.stub(songTitle: "Midnight Sun", artistName: "NILÜFER YANYA", releaseTitle: nil))
        let likedAt = store.songs[0].likedAt
        clock.advance(3600)
        store.heal(from: [Playcut.stub(songTitle: "Anotherlife", artistName: "Nilüfer Yanya", releaseTitle: nil, artistId: 1502)])
        #expect(store.songs[0].artistId == 1502)
        #expect(store.songs[0].likedAt == likedAt)
    }

    @Test("Heal never touches rows that already carry an id")
    func healSkipsIdBearing() {
        let (store, _, _) = makeStore()
        store.toggle(Playcut.stub(songTitle: "Percolator", artistName: "Stereolab", releaseTitle: nil, artistId: 118))
        store.heal(from: [Playcut.stub(songTitle: "French Disko", artistName: "Stereolab", releaseTitle: nil, artistId: 999)])
        #expect(store.songs[0].artistId == 118)
    }

    @Test("Heal with no folded-name match changes nothing and does not save")
    func healNoMatchNoSave() {
        let (store, storage, _) = makeStore()
        store.toggle(Playcut.stub(songTitle: "Utolsó tánc", artistName: "Csillagrablók", releaseTitle: nil))
        let savesBefore = storage.saveCount
        store.heal(from: [Playcut.stub(songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: nil, artistId: 812)])
        #expect(store.songs[0].artistId == nil)
        #expect(storage.saveCount == savesBefore)
    }

    @Test("A healed id survives a reload from the same storage")
    func healPersists() {
        let storage = InMemoryFileStorage()
        let (store, _, _) = makeStore(storage: storage)
        store.toggle(Playcut.stub(songTitle: "Midnight Sun", artistName: "NILÜFER YANYA", releaseTitle: nil))
        store.heal(from: [Playcut.stub(songTitle: "Anotherlife", artistName: "Nilüfer Yanya", releaseTitle: nil, artistId: 1502)])
        let (reloaded, _, _) = makeStore(storage: storage)
        #expect(reloaded.songs.first?.artistId == 1502)
    }

    // MARK: - For You projection + analytics bucket

    @Test("likedArtistIds is the distinct non-nil id set across liked songs")
    func likedArtistIds() {
        let (store, _, _) = makeStore()
        store.toggle(Playcut.stub(songTitle: "Metronomic Underground", artistName: "Stereolab", releaseTitle: nil, artistId: 118))
        store.toggle(Playcut.stub(songTitle: "Percolator", artistName: "Stereolab", releaseTitle: nil, artistId: 118))
        store.toggle(Playcut.stub(songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: nil, artistId: 812))
        store.toggle(Playcut.stub(songTitle: "Midnight Sun", artistName: "NILÜFER YANYA", releaseTitle: nil))
        #expect(store.likedArtistIds == [118, 812])
    }

    @Test("totalBucket boundaries", arguments: [
        (0, "0"), (1, "1-9"), (9, "1-9"), (10, "10-49"), (49, "10-49"), (50, "50+"),
    ])
    func totalBuckets(count: Int, expected: String) {
        let (store, _, _) = makeStore()
        for i in 0..<count {
            store.toggle(Playcut.stub(songTitle: "Song \(i)", artistName: "Artist \(i)", releaseTitle: nil))
        }
        #expect(store.totalBucket == expected)
    }

    // MARK: - Persistence

    @Test("A new store over the same storage loads the persisted songs")
    func roundTrip() {
        let storage = InMemoryFileStorage()
        let (store, _, clock) = makeStore(storage: storage)
        store.toggle(Playcut.stub(songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: nil, artistId: 812))
        clock.advance(60)
        store.toggle(Playcut.stub(songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: nil, artistId: 645))
        let (reloaded, _, _) = makeStore(storage: storage)
        #expect(reloaded.songs.map(\.songTitle) == ["la paradoja", "Back, Baby"])
        #expect(reloaded.isLiked(artistName: "jessica pratt", songTitle: "back, baby"))
    }

    @Test("Corrupt stored data loads as an empty store and recovers on the next like")
    func corruptDataRecovers() {
        let storage = InMemoryFileStorage(initial: Data("not json".utf8))
        let (store, _, _) = makeStore(storage: storage)
        #expect(store.songs.isEmpty)
        store.toggle(Playcut.stub(songTitle: "El Bueno y el Malo", artistName: "Hermanos Gutiérrez", releaseTitle: nil, artistId: 2088))
        let (reloaded, _, _) = makeStore(storage: storage)
        #expect(reloaded.songs.count == 1)
    }
}
