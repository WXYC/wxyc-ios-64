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
import LikedSongsTesting
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

private func makePlaycut(
    artist: String,
    title: String,
    album: String? = nil,
    label: String? = nil,
    artistId: Int? = nil,
    artwork: String? = nil
) -> Playcut {
    Playcut(
        id: 1,
        hour: 1,
        chronOrderID: 1,
        timeCreated: 1,
        songTitle: title,
        labelName: label,
        artistName: artist,
        releaseTitle: album,
        artworkURL: artwork.flatMap { URL(string: $0) },
        artistId: artistId
    )
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
        let liked = store.toggle(makePlaycut(
            artist: "Jessica Pratt", title: "Back, Baby",
            album: "On Your Own Love Again", label: "Drag City",
            artistId: 812, artwork: "https://example.org/oyola.jpg"
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
        store.toggle(makePlaycut(artist: "Juana Molina", title: "la paradoja"))
        let liked = store.toggle(makePlaycut(artist: "Juana Molina", title: "la paradoja"))
        #expect(liked == false)
        #expect(store.songs.isEmpty)
        #expect(storage.saveCount == 2)
    }

    @Test("The same song across releases, casing, and linkage is one liked song")
    func dedupesAcrossVariants() {
        let (store, _, _) = makeStore()
        store.toggle(makePlaycut(
            artist: "Chuquimamani-Condori", title: "Call Your Name",
            album: "Edits", artistId: 977
        ))
        // Free-text ALL-CAPS replay of the same song, different (absent) album:
        // same folded identity, so this toggle unlikes the existing row.
        let liked = store.toggle(makePlaycut(artist: "CHUQUIMAMANI-CONDORI", title: "CALL YOUR NAME"))
        #expect(liked == false)
        #expect(store.songs.isEmpty)
    }

    @Test("isLiked matches across casing and diacritics")
    func isLikedFolds() {
        let (store, _, _) = makeStore()
        store.toggle(makePlaycut(artist: "Nilüfer Yanya", title: "Midnight Sun"))
        #expect(store.isLiked(artistName: "NILUFER  YANYA", songTitle: "midnight sun"))
        #expect(!store.isLiked(artistName: "Nilüfer Yanya", songTitle: "Anotherlife"))
    }

    @Test("Songs sort newest first")
    func newestFirst() {
        let (store, _, clock) = makeStore()
        store.toggle(makePlaycut(artist: "Stereolab", title: "Metronomic Underground"))
        clock.advance(60)
        store.toggle(makePlaycut(artist: "Duke Ellington & John Coltrane", title: "In a Sentimental Mood"))
        #expect(store.songs.map(\.songTitle) == ["In a Sentimental Mood", "Metronomic Underground"])
    }

    @Test("unlike(snapshot) removes the row — the Liked tab's swipe path")
    func unlikeSnapshot() {
        let (store, _, _) = makeStore()
        store.toggle(makePlaycut(artist: "Cat Power", title: "Cross Bones Style"))
        store.unlike(store.songs[0])
        #expect(store.songs.isEmpty)
        #expect(!store.isLiked(artistName: "Cat Power", songTitle: "Cross Bones Style"))
    }

    // MARK: - Healing

    @Test("Heal stamps the observed artist id onto folded-name matches, preserving likedAt")
    func healStamps() {
        let (store, _, clock) = makeStore()
        store.toggle(makePlaycut(artist: "NILÜFER YANYA", title: "Midnight Sun"))
        let likedAt = store.songs[0].likedAt
        clock.advance(3600)
        store.heal(from: [makePlaycut(artist: "Nilüfer Yanya", title: "Anotherlife", artistId: 1502)])
        #expect(store.songs[0].artistId == 1502)
        #expect(store.songs[0].likedAt == likedAt)
    }

    @Test("Heal never touches rows that already carry an id")
    func healSkipsIdBearing() {
        let (store, _, _) = makeStore()
        store.toggle(makePlaycut(artist: "Stereolab", title: "Percolator", artistId: 118))
        store.heal(from: [makePlaycut(artist: "Stereolab", title: "French Disko", artistId: 999)])
        #expect(store.songs[0].artistId == 118)
    }

    @Test("Heal with no folded-name match changes nothing and does not save")
    func healNoMatchNoSave() {
        let (store, storage, _) = makeStore()
        store.toggle(makePlaycut(artist: "Csillagrablók", title: "Utolsó tánc"))
        let savesBefore = storage.saveCount
        store.heal(from: [makePlaycut(artist: "Jessica Pratt", title: "Back, Baby", artistId: 812)])
        #expect(store.songs[0].artistId == nil)
        #expect(storage.saveCount == savesBefore)
    }

    @Test("A healed id survives a reload from the same storage")
    func healPersists() {
        let storage = InMemoryFileStorage()
        let (store, _, _) = makeStore(storage: storage)
        store.toggle(makePlaycut(artist: "NILÜFER YANYA", title: "Midnight Sun"))
        store.heal(from: [makePlaycut(artist: "Nilüfer Yanya", title: "Anotherlife", artistId: 1502)])
        let (reloaded, _, _) = makeStore(storage: storage)
        #expect(reloaded.songs.first?.artistId == 1502)
    }

    // MARK: - For You projection + analytics bucket

    @Test("likedArtistIds is the distinct non-nil id set across liked songs")
    func likedArtistIds() {
        let (store, _, _) = makeStore()
        store.toggle(makePlaycut(artist: "Stereolab", title: "Metronomic Underground", artistId: 118))
        store.toggle(makePlaycut(artist: "Stereolab", title: "Percolator", artistId: 118))
        store.toggle(makePlaycut(artist: "Jessica Pratt", title: "Back, Baby", artistId: 812))
        store.toggle(makePlaycut(artist: "NILÜFER YANYA", title: "Midnight Sun"))
        #expect(store.likedArtistIds == [118, 812])
    }

    @Test("totalBucket boundaries", arguments: [
        (0, "0"), (1, "1-9"), (9, "1-9"), (10, "10-49"), (49, "10-49"), (50, "50+"),
    ])
    func totalBuckets(count: Int, expected: String) {
        let (store, _, _) = makeStore()
        for i in 0..<count {
            store.toggle(makePlaycut(artist: "Artist \(i)", title: "Song \(i)"))
        }
        #expect(store.totalBucket == expected)
    }

    // MARK: - Persistence

    @Test("A new store over the same storage loads the persisted songs")
    func roundTrip() {
        let storage = InMemoryFileStorage()
        let (store, _, clock) = makeStore(storage: storage)
        store.toggle(makePlaycut(artist: "Jessica Pratt", title: "Back, Baby", artistId: 812))
        clock.advance(60)
        store.toggle(makePlaycut(artist: "Juana Molina", title: "la paradoja", artistId: 645))
        let (reloaded, _, _) = makeStore(storage: storage)
        #expect(reloaded.songs.map(\.songTitle) == ["la paradoja", "Back, Baby"])
        #expect(reloaded.isLiked(artistName: "jessica pratt", songTitle: "back, baby"))
    }

    @Test("Corrupt stored data loads as an empty store and recovers on the next like")
    func corruptDataRecovers() {
        let storage = InMemoryFileStorage(initial: Data("not json".utf8))
        let (store, _, _) = makeStore(storage: storage)
        #expect(store.songs.isEmpty)
        store.toggle(makePlaycut(artist: "Hermanos Gutiérrez", title: "El Bueno y el Malo", artistId: 2088))
        let (reloaded, _, _) = makeStore(storage: storage)
        #expect(reloaded.songs.count == 1)
    }
}
