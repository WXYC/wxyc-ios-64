//
//  KeychainTokenStorageTests.swift
//  MusicShareKit
//
//  Integration tests for KeychainTokenStorage using the real Keychain on simulator.
//  Verifies round-trip persistence and migration from synchronizable items.
//
//  Created by Jake Bromberg on 04/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Security
import Testing
@testable import MusicShareKit

// MARK: - Keychain Constants (mirrors KeychainTokenStorage private statics)

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

        // Save with first instance
        let storage1 = makeStorage(synchronizable: false)
        try storage1.save(session)

        // Load with a fresh instance (simulates app relaunch)
        let storage2 = makeStorage(synchronizable: false)
        let loaded = try storage2.load()

        #expect(loaded?.token == session.token)
        #expect(loaded?.userId == session.userId)

        // Clean up
        try storage2.delete()
    }

    // MARK: - Migration from Synchronizable Items

    @Test("Migrates synchronizable item to non-synchronizable on load")
    func migratesSynchronizableItem() throws {
        let session = AuthSession(
            token: "sync-token-xyz",
            userId: "sync-user-456",
            createdAt: Date(),
            expiresAt: nil
        )

        // Save directly to keychain with kSecAttrSynchronizable = true (old behavior).
        // Synchronizable items require entitlements only available on iOS simulator,
        // so skip this test on macOS where swift test runs.
        let data = try JSONEncoder().encode(session)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            // -34018 (errSecMissingEntitlement) on macOS; test requires iOS simulator
            return
        }

        // Load with non-synchronizable storage — should migrate and return the session
        let storage = makeStorage(synchronizable: false)
        let loaded = try storage.load()

        #expect(loaded?.token == session.token)
        #expect(loaded?.userId == session.userId)

        // Verify the old synchronizable item is gone
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrSynchronizable as String: true
        ]
        let syncStatus = SecItemCopyMatching(syncQuery as CFDictionary, nil)
        #expect(syncStatus == errSecItemNotFound, "Old synchronizable item should have been deleted")

        // Verify the new non-synchronizable item exists
        let nonSyncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let nonSyncStatus = SecItemCopyMatching(nonSyncQuery as CFDictionary, &result)
        #expect(nonSyncStatus == errSecSuccess, "New non-synchronizable item should exist")

        // Clean up
        try storage.delete()
    }

    @Test("Migration tracks analytics event")
    func migrationTracksAnalytics() throws {
        let session = AuthSession(
            token: "analytics-token",
            userId: "analytics-user",
            createdAt: Date(),
            expiresAt: nil
        )

        // Seed a synchronizable item (skip on macOS — see migratesSynchronizableItem)
        let data = try JSONEncoder().encode(session)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { return }

        mockAnalytics.reset()
        let storage = makeStorage(synchronizable: false)
        _ = try storage.load()

        let eventNames = mockAnalytics.capturedEventNames()
        #expect(eventNames.contains("request_line_keychain_migrated_event"))

        // Clean up
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
        // Delete both synchronizable and non-synchronizable items
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }
}
