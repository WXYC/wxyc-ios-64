//
//  AuthenticationError.swift
//  MusicShareKit
//
//  Error types for anonymous authentication operations.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Errors that can occur during authentication operations.
public enum AuthenticationError: Error, LocalizedError, Sendable {

    /// Failed to read from or write to the Keychain.
    case keychainError(status: OSStatus)

    /// Network request failed.
    case networkError(Error)

    /// Server returned an error response.
    case serverError(statusCode: Int)

    /// Failed to parse the authentication response.
    case invalidResponse

    /// No stored session available and sign-in is required.
    case notAuthenticated

    /// Authentication service is not configured.
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            "Keychain error: \(status)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .serverError(let statusCode):
            "Server error: \(statusCode)"
        case .invalidResponse:
            "Invalid authentication response"
        case .notAuthenticated:
            "Not authenticated"
        case .notConfigured:
            "Authentication service not configured"
        }
    }
}
