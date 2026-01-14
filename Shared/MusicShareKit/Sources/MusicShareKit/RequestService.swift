//
//  RequestService.swift
//  MusicShareKit
//
//  Service for sending song requests to the DJ from shared tracks.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

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

        let url = URL(string: MusicShareKit.configuration.requestOMaticURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-type")

        let json: [String: Any] = ["message": message]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            throw RequestServiceError.encodingFailed
        }
        request.httpBody = jsonData

        MusicShareKit.trackEvent(
            "Request sent",
            properties: [
                "context": "RequestService",
                "message": message
            ]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                Log(.error, "No response object from request service")
                throw RequestServiceError.invalidResponse
            }
    
            if httpResponse.statusCode == 200 {
                Log(.info, "Request sent successfully. Status code: \(httpResponse.statusCode)")
                let notification = RequestSentMessage.makeNotification(RequestSentMessage(), object: RequestServiceSubject.shared)
                NotificationCenter.default.post(notification)
            } else {
                Log(.error, "Request failed. Status code: \(httpResponse.statusCode)")
                Log(.error, "Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw RequestServiceError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as RequestServiceError {
            throw error
        } catch {
            Log(.error, "Error sending request: \(error)")
            MusicShareKit.trackEvent(
                "$exception",
                properties: [
                    "context": "RequestService",
                    "$exception_message": error.localizedDescription
                ]
            )
            throw RequestServiceError.networkError(error)
        }
    }
    
    /// Sends a request for a specific track
    /// - Parameters:
    ///   - title: The song title
    ///   - artist: The artist name
    ///   - url: Optional URL to the track (e.g., Spotify, Apple Music link)
    public func sendRequest(title: String, artist: String, album: String? = nil) async throws {
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

    public var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Request message cannot be empty"
        case .encodingFailed:
            return "Failed to encode request data"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode):
            return "Server returned error status code: \(statusCode)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
