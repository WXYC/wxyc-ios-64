//
//  AdaptiveProfileStore.swift
//  Wallpaper
//
//  Persistent storage for learned adaptive profiles.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Persists thermal profiles to UserDefaults with device migration detection.
///
/// Profiles are stored in UserDefaults (backed up across devices). On launch,
/// the store checks if the device identifier has changed and wipes all profiles
/// if so, since thermal profiles are device-specific optimizations.
///
/// Keys use the format `thermal.profile.<shaderId>`.
@MainActor
public final class AdaptiveProfileStore: Sendable {

    /// Shared instance using standard UserDefaults.
    public static let shared = AdaptiveProfileStore()

    private let defaults: DefaultsStorage
    private let keyPrefix = "thermal.profile."
    private let deviceIdKey = "thermal.deviceIdentifier"

    /// In-memory cache for synchronous reads.
    private var memoryCache: [String: AdaptiveProfile] = [:]

    /// Creates a store with the specified defaults storage.
    ///
    /// Checks for device migration on init and wipes profiles if needed.
    ///
    /// - Parameter defaults: The storage instance to use for persistence.
    public init(defaults: DefaultsStorage = UserDefaults.standard) {
        self.defaults = defaults
        checkDeviceMigration()
    }

    /// Loads a profile for the specified shader.
    ///
    /// Returns the cached profile if available, otherwise loads from disk.
    /// If no profile exists, creates and returns a default profile.
    ///
    /// - Parameter shaderId: The shader identifier.
    /// - Returns: The thermal profile for the shader.
    public func load(shaderId: String) -> AdaptiveProfile {
        if let cached = memoryCache[shaderId] {
            return cached
        }

        let key = keyPrefix + shaderId

        if let data = defaults.data(forKey: key),
           let profile = try? JSONDecoder().decode(AdaptiveProfile.self, from: data) {
            memoryCache[shaderId] = profile
            return profile
        }

        // No cached profile, create default
        let profile = AdaptiveProfile(shaderId: shaderId)
        memoryCache[shaderId] = profile
        return profile
    }

    /// Returns the cached profile synchronously, or nil if not loaded.
    ///
    /// - Parameter shaderId: The shader identifier.
    /// - Returns: The cached profile, or nil if not in memory.
    public func cachedProfile(for shaderId: String) -> AdaptiveProfile? {
        memoryCache[shaderId]
    }

    /// Saves a profile to disk and updates the cache.
    ///
    /// - Parameter profile: The profile to save.
    public func save(_ profile: AdaptiveProfile) {
        memoryCache[profile.shaderId] = profile

        let key = keyPrefix + profile.shaderId
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: key)
        }
    }

    /// Removes a profile for the specified shader.
    ///
    /// - Parameter shaderId: The shader identifier.
    public func remove(shaderId: String) {
        memoryCache.removeValue(forKey: shaderId)
        defaults.removeObject(forKey: keyPrefix + shaderId)
    }

    /// Clears all cached profiles from memory (disk profiles remain).
    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    /// Removes all thermal profiles from memory and disk.
    ///
    /// Use this to reset learned thermal behavior for all shaders.
    public func removeAllProfiles() {
        memoryCache.removeAll()

        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Device Migration

    private func checkDeviceMigration() {
        let currentDeviceId = currentDeviceIdentifier
        let storedDeviceId = defaults.string(forKey: deviceIdKey)

        if let storedDeviceId, storedDeviceId != currentDeviceId {
            // Device has changed, wipe all thermal profiles
            removeAllProfiles()
        }

        // Store current device ID
        defaults.set(currentDeviceId, forKey: deviceIdKey)
    }

    private var currentDeviceIdentifier: String {
        #if canImport(UIKit) && !os(watchOS)
        // Use identifierForVendor - stable for same vendor's apps on a device
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        #endif
        // Fallback: use a generated UUID stored in Keychain would be better,
        // but for simplicity use model name (will trigger re-learning on new device)
        return ProcessInfo.processInfo.hostName
    }
}
