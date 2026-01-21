//
//  AuthenticationService.swift
//  MusicShareKit
//
//  Main actor orchestrating anonymous authentication flow.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation

/// Service for managing anonymous authentication.
///
/// Handles token caching, Keychain persistence, and network sign-in.
/// All operations are serialized to prevent race conditions.
public actor AuthenticationService {

    // MARK: - Dependencies

    private let storage: TokenStorage
    private let networkClient: AuthNetworkClient
    private let baseURL: String
    private let analytics: AnalyticsService

    // MARK: - State

    /// In-memory cached session for fast access.
    private var cachedSession: AuthSession?

    // MARK: - Initialization

    /// Creates a new authentication service.
    ///
    /// - Parameters:
    ///   - storage: The token storage implementation.
    ///   - networkClient: The network client for sign-in requests.
    ///   - baseURL: The base URL for the authentication API.
    ///   - analytics: Analytics service for tracking auth events.
    public init(
        storage: TokenStorage,
        networkClient: AuthNetworkClient,
        baseURL: String,
        analytics: AnalyticsService
    ) {
        self.storage = storage
        self.networkClient = networkClient
        self.baseURL = baseURL
        self.analytics = analytics
    }

    // MARK: - Public API

    /// Ensures the user is authenticated and returns a valid token.
    ///
    /// Flow:
    /// 1. Return cached token if available and not expired
    /// 2. Load from Keychain if not in cache
    /// 3. Sign in anonymously if no stored session
    ///
    /// - Returns: A valid bearer token.
    /// - Throws: `AuthenticationError` if authentication fails.
    public func ensureAuthenticated() async throws -> String {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. Check memory cache
        if let session = cachedSession, !session.isExpired {
            trackAuthCompleted(source: .cache, startTime: startTime, success: true)
            return session.token
        }

        trackAuthStarted(source: .keychain)

        // 2. Try to load from Keychain
        do {
            if let session = try storage.load(), !session.isExpired {
                cachedSession = session
                trackAuthCompleted(source: .keychain, startTime: startTime, success: true)
                return session.token
            }
        } catch {
            // Log but continue to network sign-in
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .keychain
            ))
        }

        trackAuthStarted(source: .network)

        // 3. Sign in anonymously
        let session: AuthSession
        do {
            session = try await networkClient.signInAnonymously(baseURL: baseURL)
        } catch {
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .network
            ))
            throw error
        }

        // Save to Keychain
        do {
            try storage.save(session)
        } catch {
            // Log but don't fail - we have a valid session
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .keychain
            ))
        }

        cachedSession = session
        trackAuthCompleted(source: .network, startTime: startTime, success: true)
        return session.token
    }

    /// Forces reauthentication, clearing cached and stored sessions.
    ///
    /// Call this when receiving a 401 response to get a fresh token.
    ///
    /// - Parameter reason: The reason for reauthentication.
    /// - Returns: A fresh bearer token.
    /// - Throws: `AuthenticationError` if authentication fails.
    public func reauthenticate(reason: TokenRefreshReason) async throws -> String {
        analytics.capture(RequestLineTokenRefreshedEvent(reason: reason, success: true))

        // Clear cached session
        cachedSession = nil

        // Clear stored session
        do {
            try storage.delete()
        } catch {
            // Log but continue
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .keychain
            ))
        }

        // Get fresh token
        return try await ensureAuthenticated()
    }

    /// Returns the current user ID if authenticated.
    ///
    /// - Returns: The user ID, or `nil` if not authenticated.
    public func currentUserId() async -> String? {
        if let session = cachedSession, !session.isExpired {
            return session.userId
        }

        do {
            if let session = try storage.load(), !session.isExpired {
                cachedSession = session
                return session.userId
            }
        } catch {
            // Ignore errors
        }

        return nil
    }

    /// Clears all authentication state.
    public func signOut() async {
        cachedSession = nil
        try? storage.delete()
    }

    // MARK: - Analytics

    private func trackAuthStarted(source: AuthTokenSource) {
        analytics.capture(RequestLineAuthStartedEvent(source: source))
    }

    private func trackAuthCompleted(source: AuthTokenSource, startTime: CFAbsoluteTime, success: Bool) {
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        analytics.capture(RequestLineAuthCompletedEvent(
            source: source,
            durationMs: duration,
            success: success
        ))
    }
}
