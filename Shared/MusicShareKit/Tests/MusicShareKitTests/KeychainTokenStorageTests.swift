//
//  KeychainTokenStorageTests.swift
//  MusicShareKit
//
//  Integration tests for KeychainTokenStorage using the real Keychain.
//  Verifies round-trip persistence, synchronizable fallback, and load fallback.
//
//  Created by Jake Bromberg on 04/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Security
import Testing
@testable import MusicShareKit

private let testService = "org.wxyc.app.auth.test"
private let testAccount = "anonymous-session-test"

@Suite("KeychainTokenStorage Tests", .serialized)
struct KeychainTokenStorageTests {

    let mockAnalytics = MockStructuredAnalytics()

    init() {
        // Clean up any leftover items from prior test runs
        deleteAllTestKeychainItems()
    }

    // MARK: - Round-Trip Persistence

    @Test("Save and load round-trips session across instances")
    func saveAndLoadRoundTripsAcrossInstances() throws {
        let session = AuthSession(
            token: "persist-token-abc",
            userId: "persist-user-123",
            createdAt: Date(),
            expiresAt: nil
        )

        let storage1 = makeStorage(synchronizable: false)
        try storage1.save(session)

        // Load with a fresh instance (simulates app relaunch)
        let storage2 = makeStorage(synchronizable: false)
        let loaded = try storage2.load()

        #expect(loaded?.token == session.token)
        #expect(loaded?.userId == session.userId)

        try storage2.delete()
    }

    // MARK: - Synchronizable Save Fallback

    @Test("Save falls back to non-synchronizable when iCloud Keychain is unavailable")
    func saveFallsBackToNonSynchronizable() throws {
        let session = AuthSession(
            token: "fallback-token-xyz",
            userId: "fallback-user-456",
            createdAt: Date(),
            expiresAt: nil
        )

        // Save with synchronizable=true. On macOS (swift test), iCloud Keychain
        // is unavailable, so the sync save fails and falls back to non-sync.
        let storage = makeStorage(synchronizable: true)
        try storage.save(session)

        // Load should find the item regardless of how it was saved
        let loaded = try storage.load()
        #expect(loaded?.token == session.token)
        #expect(loaded?.userId == session.userId)

        try storage.delete()
    }

    @Test("Save fallback persists across instances")
    func saveFallbackPersistsAcrossInstances() throws {
        let session = AuthSession(
            token: "relaunch-token",
            userId: "relaunch-user",
            createdAt: Date(),
            expiresAt: nil
        )

        // Save with synchronizable=true (may fall back to non-sync)
        let storage1 = makeStorage(synchronizable: true)
        try storage1.save(session)

        // Load with a fresh synchronizable=true instance (simulates app relaunch)
        let storage2 = makeStorage(synchronizable: true)
        let loaded = try storage2.load()

        #expect(loaded?.token == session.token)
        #expect(loaded?.userId == session.userId)

        try storage2.delete()
    }

    // MARK: - Load Fallback

    @Test("Load with synchronizable=true finds non-synchronizable items")
    func loadFindsFallbackItems() throws {
        let session = AuthSession(
            token: "nonsync-token",
            userId: "nonsync-user",
            createdAt: Date(),
            expiresAt: nil
        )

        // Save directly as non-synchronizable (simulates a fallback save)
        let data = try JSONEncoder().encode(session)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        #expect(addStatus == errSecSuccess)

        // Load with synchronizable=true should still find the non-sync item
        let storage = makeStorage(synchronizable: true)
        let loaded = try storage.load()

        #expect(loaded?.token == session.token)
        #expect(loaded?.userId == session.userId)

        try storage.delete()
    }

    // MARK: - Helpers

    private func makeStorage(synchronizable: Bool) -> KeychainTokenStorage {
        KeychainTokenStorage(
            service: testService,
            account: testAccount,
            accessGroup: nil,
            synchronizable: synchronizable,
            analytics: mockAnalytics
        )
    }

    private func deleteAllTestKeychainItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)

        // Also delete non-synchronizable items (queries without kSecAttrSynchronizable
        // won't match synchronizable items and vice versa)
        let nonSyncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount
        ]
        SecItemDelete(nonSyncQuery as CFDictionary)
    }
}
