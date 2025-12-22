//
//  MusicShareKitConfiguration.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 12/22/25.
//

import Foundation

/// Configuration for MusicShareKit services.
/// Must be set before using RequestService or ShareExtensionView.
public struct MusicShareKitConfiguration: Sendable {
    /// The URL for the request-o-matic service
    public let requestOMaticURL: String

    /// Spotify API client ID
    public let spotifyClientId: String

    /// Spotify API client secret
    public let spotifyClientSecret: String

    /// Optional analytics handler for tracking events
    public let analyticsHandler: (@Sendable (String, [String: Any]) -> Void)?

    public init(
        requestOMaticURL: String,
        spotifyClientId: String,
        spotifyClientSecret: String,
        analyticsHandler: (@Sendable (String, [String: Any]) -> Void)? = nil
    ) {
        self.requestOMaticURL = requestOMaticURL
        self.spotifyClientId = spotifyClientId
        self.spotifyClientSecret = spotifyClientSecret
        self.analyticsHandler = analyticsHandler
    }
}

/// Global configuration storage for MusicShareKit
public enum MusicShareKit {
    // Safe because configuration is set once at app startup before any access
    nonisolated(unsafe) private static var _configuration: MusicShareKitConfiguration?

    /// The current configuration. Fatal error if not set.
    public static var configuration: MusicShareKitConfiguration {
        guard let config = _configuration else {
            fatalError("MusicShareKit.configure() must be called before using MusicShareKit services")
        }
        return config
    }

    /// Configure MusicShareKit with the required settings.
    /// Call this early in your app's lifecycle before using any MusicShareKit services.
    public static func configure(_ configuration: MusicShareKitConfiguration) {
        _configuration = configuration
    }

    /// Tracks an analytics event if an analytics handler is configured.
    static func trackEvent(_ event: String, properties: [String: Any]) {
        configuration.analyticsHandler?(event, properties)
    }
}
