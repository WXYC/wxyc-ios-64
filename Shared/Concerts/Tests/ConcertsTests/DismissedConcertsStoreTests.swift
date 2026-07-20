//
//  DismissedConcertsStoreTests.swift
//  Concerts
//
//  Coverage for the "Not interested" store behind the For You shelf: dismiss
//  records + persists, a fresh store reloads prior dismissals, resetState clears,
//  and an unreadable file recovers to empty. Exercises the real
//  load/decode/encode/save paths through an in-memory `FileStorage` double.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

@MainActor
@Suite("DismissedConcertsStore")
struct DismissedConcertsStoreTests {

    /// A store over a fresh in-memory file, returning both so tests can assert on
    /// the persisted bytes. `initial` seeds an existing (or corrupt) store file.
    private func makeStore(initial: Data? = nil) -> (DismissedConcertsStore, InMemoryFileStorage) {
        let storage = InMemoryFileStorage(initial: initial)
        return (DismissedConcertsStore(storage: storage), storage)
    }

    private func encodedIDs(_ ids: [Int]) throws -> Data {
        try JSONEncoder().encode(ids)
    }

    private func decodedIDs(_ data: Data?) throws -> [Int] {
        try JSONDecoder().decode([Int].self, from: try #require(data)).sorted()
    }

    @Test("A new store with no file starts empty")
    func startsEmpty() {
        let (store, _) = makeStore()
        #expect(store.ids.isEmpty)
    }

    @Test("Dismiss records the id")
    func dismissRecords() {
        let (store, _) = makeStore()
        store.dismiss(1)
        #expect(store.ids == [1])
    }

    @Test("Dismiss writes the set through to storage")
    func dismissPersists() throws {
        let (store, storage) = makeStore()
        store.dismiss(7)
        store.dismiss(3)
        #expect(storage.saveCount == 2)
        #expect(try decodedIDs(storage.contents) == [3, 7])
    }

    @Test("Dismissing an already-dismissed id is a no-op — no redundant write")
    func dismissIdempotent() {
        let (store, storage) = makeStore()
        store.dismiss(1)
        store.dismiss(1)
        #expect(store.ids == [1])
        #expect(storage.saveCount == 1)
    }

    @Test("A fresh store reloads previously-dismissed ids")
    func reloadsPriorDismissals() throws {
        let seeded = try encodedIDs([2, 5])
        let (store, _) = makeStore(initial: seeded)
        #expect(store.ids == [2, 5])
    }

    @Test("resetState clears the set and persists the empty state")
    func resetClearsAndPersists() throws {
        let (store, storage) = makeStore()
        store.dismiss(1)
        store.dismiss(2)
        store.resetState()
        #expect(store.ids.isEmpty)
        #expect(try decodedIDs(storage.contents) == [])
    }

    @Test("resetState on an empty store does not write")
    func resetEmptyNoWrite() {
        let (store, storage) = makeStore()
        store.resetState()
        #expect(storage.saveCount == 0)
    }

    @Test("An unreadable store file recovers to empty rather than crashing")
    func corruptRecoversEmpty() {
        let garbage = Data("not json".utf8)
        let (store, _) = makeStore(initial: garbage)
        #expect(store.ids.isEmpty)
    }
}
