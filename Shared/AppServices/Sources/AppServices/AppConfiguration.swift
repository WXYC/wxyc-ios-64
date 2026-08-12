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
import Core
import Logger

/// App configuration values returned by the public `/config` endpoint.
public struct AppConfig: Sendable, Codable, Equatable {
    public let posthogApiKey: String
    public let posthogHost: String
    public let requestOMaticUrl: String
    public let apiBaseUrl: String

    /// The canonical hosted donation page, or `nil` when the backend predates
    /// the field.
    ///
    /// Backend-Service serves `""` (not `null`) when `DONATE_URL` is unset on
    /// Railway, following the established `process.env.X || ''` controller
    /// shape — so consumers must treat an empty or unparseable value as
    /// *absent* and fall through to the next rung of the ladder rather than
    /// letting it silently produce no destination. ``DonateRowModel`` does.
    public let donateUrl: String?

    /// Whether to show the Donate row at all, or `nil` when the backend
    /// predates the field.
    ///
    /// This is a **deploy-time** switch, not an instant kill switch: `/config`
    /// is served `Cache-Control: public, max-age=3600`, so a flip takes up to
    /// an hour to propagate.
    public let donateEnabled: Bool?

    /// - Note: Both donate parameters are defaulted because this initializer is
    ///   hand-written rather than synthesized-memberwise — undefaulted
    ///   parameters would break every existing construction site.
    public init(
        posthogApiKey: String,
        posthogHost: String,
        requestOMaticUrl: String,
        apiBaseUrl: String,
        donateUrl: String? = nil,
        donateEnabled: Bool? = nil
    ) {
        self.posthogApiKey = posthogApiKey
        self.posthogHost = posthogHost
        self.requestOMaticUrl = requestOMaticUrl
        self.apiBaseUrl = apiBaseUrl
        self.donateUrl = donateUrl
        self.donateEnabled = donateEnabled
    }
}

/// Third-party API credentials returned by the authenticated `/config/secrets` endpoint.
public struct AppSecrets: Sendable, Codable, Equatable {
    public let discogsApiKey: String
    public let discogsApiSecret: String
}

/// Bootstrap configuration provider.
///
/// Provides hardcoded defaults that are always available synchronously (for widgets,
/// extensions, and first launch) and optionally fetches from the backend `/config`
/// endpoint to pick up configuration changes without an app update.
///
/// Third-party API credentials are served from the authenticated `/config/secrets`
/// endpoint and require a session token.
public actor AppConfiguration {
    /// The backend API base URL. This is the only value that must be known at compile time.
    public static let apiBaseUrl = "https://api.wxyc.org"

    /// The Sentry DSN for crash reporting. Safe to embed (Sentry documents that DSNs are not secrets).
    public static let sentryDsn = "https://cf27cd29a02232e1a0f2682c7138119b@o4510807758143488.ingest.us.sentry.io/4510982175784960"

    /// The Keychain access group shared between the main app and Share Extension.
    ///
    /// Used so a session cached by one target is readable by the other. Must match the
    /// `keychain-access-groups` entitlement on every target that calls `MusicShareKit.configure(...)`.
    /// Format is `<TeamID>.<group-name>`; `$(AppIdentifierPrefix)` resolves to the team ID at
    /// build time in entitlement plists, but code references need it expanded literally.
    public static let keychainAccessGroup = "92V374HC38.group.wxyc.iphone"

    /// Hardcoded defaults for when the network is unavailable.
    ///
    /// - Important: `donateEnabled` is pinned to `false` **explicitly** rather
    ///   than left to the initializer's `nil` default. ``config()`` returns this
    ///   literal on every failure path, so it is what cold launch, airplane
    ///   mode, and a backend blip render — and `nil` would resolve to
    ///   ``DonateRowModel``'s `?? true`, showing the row in exactly the release
    ///   meant to ship dark. Lighting up is two steps: set `DONATE_ENABLED=true`
    ///   on Railway (no app release), then flip this literal in the next
    ///   regular release so offline launches show the row too.
    public static let defaults = AppConfig(
        posthogApiKey: "phc_jUWlgO0aQzyPgHqQUEC7VPD1IdN1tytHG3qckb7CLoD",
        posthogHost: "https://us.i.posthog.com",
        requestOMaticUrl: "https://request-o-matic-production.up.railway.app/request",
        apiBaseUrl: apiBaseUrl,
        donateEnabled: false
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

            let config = try JSONDecoder.shared.decode(AppConfig.self, from: data)
            cached = config
            return config
        } catch {
            Log(.warning, category: .general, "AppConfiguration: failed to fetch /config: \(error.localizedDescription)")
            return Self.defaults
        }
    }

    /// Fetches third-party API credentials from the authenticated `/config/secrets` endpoint.
    ///
    /// Goes through `URLSession.authedData(for:tokenProvider:)`, the shared
    /// authed-request seam: a stale-token 401 (the #715 cold-launch
    /// condition) reauthenticates and retries once instead of silently
    /// collapsing to `nil` — which would leave the Discogs artwork fallback
    /// disabled for the whole session.
    ///
    /// Returns `nil` on failure (no auth session, network error, persistent
    /// non-2xx, or backend hasn't been updated yet).
    public func fetchSecrets(tokenProvider: SessionTokenProvider) async -> AppSecrets? {
        do {
            let url = URL(string: "\(Self.apiBaseUrl)/config/secrets")!
            let request = URLRequest(url: url)
            let (data, _) = try await session.authedData(for: request, tokenProvider: tokenProvider)
            return try JSONDecoder.shared.decode(AppSecrets.self, from: data)
        } catch {
            Log(.warning, category: .general, "AppConfiguration: failed to fetch /config/secrets: \(error)")
            return nil
        }
    }
}
