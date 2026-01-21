//
//  RequestService.swift
//  MusicShareKit
//
//  Service for sending song requests to the DJ from shared tracks.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import Core
import Foundation
import Logger

/// Subject for RequestSentMessage notifications.
public final class RequestServiceSubject: @unchecked Sendable {
    public static let shared = RequestServiceSubject()
    private init() {}
}

/// Message posted when a song request is successfully sent.
public struct RequestSentMessage: AsyncNotificationMessage, Sendable {
    public typealias Subject = RequestServiceSubject

    public static var name: Notification.Name { .init("MusicShareKit.RequestSent") }

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self, object: Subject?) -> Notification {
        Notification(name: name, object: object)
    }
}

/// A service for sending song requests to WXYC
public struct RequestService: Sendable {
    public static let shared = RequestService()

    private init() {}

    /// Sends a request message to the WXYC request service
    /// - Parameter message: The request message (e.g., "Song Title by Artist Name")
    /// - Throws: RequestServiceError if the request fails
    public func sendRequest(message: String) async throws {
        guard !message.isEmpty else {
            throw RequestServiceError.emptyMessage
        }

        let useAuth = MusicShareKit.isAuthEnabled()
        try await sendRequestInternal(message: message, useAuth: useAuth, isRetry: false)
    }

    /// Internal implementation with retry support for 401 responses.
    private func sendRequestInternal(message: String, useAuth: Bool, isRetry: Bool) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        let url = URL(string: MusicShareKit.configuration.requestOMaticURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-type")

        // Add auth header if enabled
        if useAuth, let authService = MusicShareKit.authService {
            do {
                let token = try await authService.ensureAuthenticated()
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } catch {
                Log(.error, category: .network, "Failed to authenticate: \(error)")
                throw RequestServiceError.authenticationFailed(error)
            }
        }

        let json: [String: Any] = ["message": message]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            throw RequestServiceError.encodingFailed
        }
        request.httpBody = jsonData

        // Track request attempt - using generic event for now
        // The request completion event below has the detailed tracking

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            guard let httpResponse = response as? HTTPURLResponse else {
                Log(.error, category: .network, "No response object from request service")
                throw RequestServiceError.invalidResponse
            }

            // Track request completion
            MusicShareKit.configuration.analyticsService.capture(
                RequestLineRequestCompletedEvent(
                    authenticated: useAuth,
                    statusCode: httpResponse.statusCode,
                    durationMs: duration
                )
            )

            switch httpResponse.statusCode {
            case 200:
                Log(.info, category: .network, "Request sent successfully. Status code: \(httpResponse.statusCode)")
                let notification = RequestSentMessage.makeNotification(RequestSentMessage(), object: RequestServiceSubject.shared)
                NotificationCenter.default.post(notification)

            case 401 where useAuth && !isRetry:
                // Token expired - reauthenticate and retry once
                Log(.info, category: .network, "Got 401, reauthenticating...")
                if let authService = MusicShareKit.authService {
                    _ = try await authService.reauthenticate(reason: .unauthorized)
                    try await sendRequestInternal(message: message, useAuth: useAuth, isRetry: true)
                } else {
                    throw RequestServiceError.serverError(statusCode: httpResponse.statusCode)
                }

            case 403 where useAuth:
                // User is banned
                let userId = await MusicShareKit.authService?.currentUserId()
                MusicShareKit.configuration.analyticsService.capture(
                    RequestLineUserBannedEvent(userId: userId ?? "unknown")
                )
                Log(.error, category: .network, "User banned from request service")
                throw RequestServiceError.userBanned

            default:
                Log(.error, category: .network, "Request failed. Status code: \(httpResponse.statusCode)")
                Log(.error, category: .network, "Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw RequestServiceError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as RequestServiceError {
            throw error
        } catch {
            Log(.error, category: .network, "Error sending request: \(error)")
            throw RequestServiceError.networkError(error)
        }
    }

    /// Sends a request for a specific track
    /// - Parameters:
    ///   - title: The song title
    ///   - artist: The artist name
    ///   - url: Optional URL to the track (e.g., Spotify, Apple Music link)
    public func sendRequest(title: String, artist: String, album _: String? = nil) async throws {
        let message = "\(title) by \(artist)"
        try await sendRequest(message: message)
    }
}

/// Errors that can occur when sending requests
public enum RequestServiceError: Error, LocalizedError {
    case emptyMessage
    case encodingFailed
    case invalidResponse
    case serverError(statusCode: Int)
    case networkError(Error)
    case authenticationFailed(Error)
    case userBanned

    public var errorDescription: String? {
        switch self {
        case .emptyMessage:
            "Request message cannot be empty"
        case .encodingFailed:
            "Failed to encode request data"
        case .invalidResponse:
            "Invalid response from server"
        case .serverError(let statusCode):
            "Server returned error status code: \(statusCode)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .authenticationFailed(let error):
            "Authentication failed: \(error.localizedDescription)"
        case .userBanned:
            "You have been banned from making requests"
        }
    }
}
