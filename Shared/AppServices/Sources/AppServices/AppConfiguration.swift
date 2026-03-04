//
//  AppConfiguration.swift
//  AppServices
//
//  Bootstrap configuration for the app. Provides hardcoded defaults for widgets and extensions,
//  and optionally fetches from the backend `/config` endpoint for the main app.
//
//  Created by Jake Bromberg on 03/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger

/// App configuration values returned by the `/config` endpoint.
public struct AppConfig: Sendable, Codable, Equatable {
    public let posthogApiKey: String
    public let posthogHost: String
    public let requestOMaticUrl: String
    public let apiBaseUrl: String

    public init(
        posthogApiKey: String,
        posthogHost: String,
        requestOMaticUrl: String,
        apiBaseUrl: String
    ) {
        self.posthogApiKey = posthogApiKey
        self.posthogHost = posthogHost
        self.requestOMaticUrl = requestOMaticUrl
        self.apiBaseUrl = apiBaseUrl
    }
}

/// Bootstrap configuration provider.
///
/// Provides hardcoded defaults that are always available synchronously (for widgets,
/// extensions, and first launch) and optionally fetches from the backend `/config`
/// endpoint to pick up configuration changes without an app update.
public actor AppConfiguration {
    /// The backend API base URL. This is the only value that must be known at compile time.
    public static let apiBaseUrl = "https://api.wxyc.org"

    /// The Sentry DSN for crash reporting. Safe to embed (Sentry documents that DSNs are not secrets).
    public static let sentryDsn = ""

    /// Hardcoded defaults for when the network is unavailable.
    public static let defaults = AppConfig(
        posthogApiKey: "phc_jUWlgO0aQzyPgHqQUEC7VPD1IdN1tytHG3qckb7CLoD",
        posthogHost: "https://us.i.posthog.com",
        requestOMaticUrl: "https://request-o-matic-production.up.railway.app/request",
        apiBaseUrl: apiBaseUrl
    )

    private var cached: AppConfig?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns the configuration, fetching from the backend if not yet cached.
    ///
    /// On failure, returns ``defaults`` without caching (so the next call will retry).
    public func config() async -> AppConfig {
        if let cached { return cached }

        do {
            let url = URL(string: "\(Self.apiBaseUrl)/config")!
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Log(.warning, category: .general, "AppConfiguration: non-200 response from /config")
                return Self.defaults
            }

            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            cached = config
            return config
        } catch {
            Log(.warning, category: .general, "AppConfiguration: failed to fetch /config: \(error.localizedDescription)")
            return Self.defaults
        }
    }
}
