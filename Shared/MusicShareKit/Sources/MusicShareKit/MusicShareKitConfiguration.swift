//
//  MusicShareKitConfiguration.swift
//  MusicShareKit
//
//  Configuration for MusicShareKit endpoints and behavior.
//
//  Created by Jake Bromberg on 12/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import Caching
import Foundation

/// Configuration for MusicShareKit services.
/// Must be set before using RequestService or ShareExtensionView.
public struct MusicShareKitConfiguration {
    /// The URL for the request-o-matic service
    public let requestOMaticURL: String

    /// The base URL for the authentication API.
    /// Required for authenticated requests when the feature flag is enabled.
    public let authBaseURL: String?

    /// The Keychain access group for sharing tokens between app and extensions.
    /// Format: `$(TeamID).group.name` (e.g., `92V374HC38.group.wxyc.iphone`).
    /// Pass `nil` for app-only storage.
    public let keychainAccessGroup: String?

    /// Provider for checking feature flag values.
    /// Used to determine if authentication is enabled.
    public let featureFlagProvider: FeatureFlagProvider?

    /// Defaults storage for storing debug overrides.
    /// Uses app group defaults for sharing between app and extensions.
    public let defaults: DefaultsStorage

    /// Analytics service for tracking events.
    public let analyticsService: AnalyticsService

    /// Storage for the stable per-device fingerprint sent as `X-Device-Fingerprint`
    /// on authenticated requests. Defaults to `KeychainDeviceFingerprintStorage`
    /// scoped to the same `keychainAccessGroup` as `KeychainTokenStorage`, so
    /// main-app and share-extension see the same value.
    public let deviceFingerprintStorage: any DeviceFingerprintStorage

    public init(
        requestOMaticURL: String,
        authBaseURL: String? = nil,
        keychainAccessGroup: String? = nil,
        featureFlagProvider: FeatureFlagProvider? = nil,
        defaults: DefaultsStorage = UserDefaults.standard,
        analyticsService: AnalyticsService,
        deviceFingerprintStorage: (any DeviceFingerprintStorage)? = nil
    ) {
        self.requestOMaticURL = requestOMaticURL
        self.authBaseURL = authBaseURL
        self.keychainAccessGroup = keychainAccessGroup
        self.featureFlagProvider = featureFlagProvider
        self.defaults = defaults
        self.analyticsService = analyticsService
        self.deviceFingerprintStorage = deviceFingerprintStorage
            ?? KeychainDeviceFingerprintStorage(accessGroup: keychainAccessGroup)
    }
}

/// Global configuration storage for MusicShareKit
public enum MusicShareKit {
    // Safe because configuration is set once at app startup before any access
    nonisolated(unsafe) private static var _configuration: MusicShareKitConfiguration?
    nonisolated(unsafe) private static var _authService: AuthenticationService?
    nonisolated(unsafe) private static var _deviceFingerprint: String?
    private static let fingerprintLock = NSLock()

    /// The current configuration. Fatal error if not set.
    public static var configuration: MusicShareKitConfiguration {
        guard let config = _configuration else {
            fatalError("MusicShareKit.configure() must be called before using MusicShareKit services")
        }
        return config
    }

    /// The shared authentication service, if authentication is configured.
    public static var authService: AuthenticationService? {
        _authService
    }

    /// The stable per-device fingerprint, or `nil` if it could not be loaded.
    ///
    /// Eager init in `configure(...)` is the authoritative path that closes
    /// the cross-process race (D3 in the iOS#351 plan). The inline retry here
    /// is a defensive backstop for the narrow window where `configure()` ran
    /// pre-first-unlock (e.g., a background-launched share extension) and the
    /// actual request happens after the user has unlocked the device. The
    /// retry is NOT lazy initialization — lazy as the primary path would
    /// reintroduce the cross-process race.
    public static var deviceFingerprint: String? {
        fingerprintLock.lock()
        defer { fingerprintLock.unlock() }

        if let cached = _deviceFingerprint {
            return cached
        }

        guard let config = _configuration else {
            return nil
        }

        // Retry once. If it still fails, return nil — downstream callers omit
        // the header, ROM proceeds-as-unauth, listener can still request, the
        // ban-evasion vector temporarily opens. Analytics already captured
        // during the eager attempt in configure(); don't double-emit.
        guard let value = try? config.deviceFingerprintStorage.ensure() else {
            return nil
        }
        _deviceFingerprint = value
        return value
    }

    /// Configure MusicShareKit with the required settings.
    /// Call this early in your app's lifecycle before using any MusicShareKit services.
    public static func configure(_ configuration: MusicShareKitConfiguration) {
        _configuration = configuration

        // Eagerly materialize the device fingerprint BEFORE init'ing the auth
        // service so the fingerprint header is available on the very first
        // /sign-in/anonymous call.
        //
        // Eager (vs. lazy) is load-bearing: lazy initialization would let the
        // main app and share extension first-launch concurrently, both observe
        // an empty Keychain on their first read, and both write — Race A in
        // the iOS#351 plan. Eager init means whichever process runs configure()
        // second sees the value committed by the first via the atomic
        // add-or-reread inside ensure().
        fingerprintLock.lock()
        do {
            _deviceFingerprint = try configuration.deviceFingerprintStorage.ensure()
        } catch {
            _deviceFingerprint = nil
            configuration.analyticsService.capture(
                DeviceFingerprintInitFailedEvent(error: error.localizedDescription)
            )
        }
        fingerprintLock.unlock()

        // Initialize auth service if auth is configured
        if let authBaseURL = configuration.authBaseURL {
            let storage = KeychainTokenStorage(
                accessGroup: configuration.keychainAccessGroup,
                analytics: configuration.analyticsService
            )
            _authService = AuthenticationService(
                storage: storage,
                networkClient: DefaultAuthNetworkClient(),
                baseURL: authBaseURL,
                analytics: configuration.analyticsService
            )
        }
    }

    /// Checks if request line authentication is enabled via feature flag.
    ///
    /// - Returns: `true` if authentication should be used, `false` otherwise.
    public static func isAuthEnabled() -> Bool {
        guard let provider = configuration.featureFlagProvider else {
            return false
        }
        return RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: configuration.defaults,
            analytics: configuration.analyticsService
        )
    }
}
