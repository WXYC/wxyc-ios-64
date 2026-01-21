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

    /// Spotify API client ID
    public let spotifyClientId: String

    /// Spotify API client secret
    public let spotifyClientSecret: String

    /// Provider for checking feature flag values.
    /// Used to determine if authentication is enabled.
    public let featureFlagProvider: FeatureFlagProvider?

    /// Defaults storage for storing debug overrides.
    /// Uses app group defaults for sharing between app and extensions.
    public let defaults: DefaultsStorage

    /// Analytics service for tracking events.
    public let analyticsService: AnalyticsService

    public init(
        requestOMaticURL: String,
        authBaseURL: String? = nil,
        keychainAccessGroup: String? = nil,
        spotifyClientId: String,
        spotifyClientSecret: String,
        featureFlagProvider: FeatureFlagProvider? = nil,
        defaults: DefaultsStorage = UserDefaults.standard,
        analyticsService: AnalyticsService
    ) {
        self.requestOMaticURL = requestOMaticURL
        self.authBaseURL = authBaseURL
        self.keychainAccessGroup = keychainAccessGroup
        self.spotifyClientId = spotifyClientId
        self.spotifyClientSecret = spotifyClientSecret
        self.featureFlagProvider = featureFlagProvider
        self.defaults = defaults
        self.analyticsService = analyticsService
    }
}

/// Global configuration storage for MusicShareKit
public enum MusicShareKit {
    // Safe because configuration is set once at app startup before any access
    nonisolated(unsafe) private static var _configuration: MusicShareKitConfiguration?
    nonisolated(unsafe) private static var _authService: AuthenticationService?

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

    /// Configure MusicShareKit with the required settings.
    /// Call this early in your app's lifecycle before using any MusicShareKit services.
    public static func configure(_ configuration: MusicShareKitConfiguration) {
        _configuration = configuration

        // Initialize auth service if auth is configured
        if let authBaseURL = configuration.authBaseURL {
            let storage = KeychainTokenStorage(
                accessGroup: configuration.keychainAccessGroup,
                synchronizable: true,
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
