//
//  RequestServiceTests.swift
//  MusicShareKit
//
//  Tests for RequestService song request behavior.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import MusicShareKit

@Suite("RequestService Tests")
struct RequestServiceTests {
    
    init() {
        // Configure MusicShareKit before running tests
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            spotifyClientId: "test-client-id",
            spotifyClientSecret: "test-client-secret"
        ))
    }
    
    @Test("Empty message throws error")
    func emptyMessageThrowsError() async {
        do {
            try await RequestService.shared.sendRequest(message: "")
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as RequestServiceError {
            #expect(error == .emptyMessage)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
    
    @Test("Configuration is accessible after configure() is called")
    func configurationIsAccessible() {
        let config = MusicShareKit.configuration
        #expect(config.requestOMaticURL == "https://example.com/request")
        #expect(config.spotifyClientId == "test-client-id")
        #expect(config.spotifyClientSecret == "test-client-secret")
    }
    
    @Test("sendRequest uses configured URL")
    func sendRequestUsesConfiguredURL() async {
        // This test verifies that sendRequest accesses the configuration
        // without crashing. The actual network request will fail (expected),
        // but we verify it gets past the configuration access.
        do {
            try await RequestService.shared.sendRequest(message: "Test Song by Test Artist")
            // If we get here without a network error, the test server responded
        } catch RequestServiceError.networkError {
            // Expected - the test URL doesn't exist
        } catch RequestServiceError.invalidResponse {
            // Also acceptable - server responded but not as expected
        } catch RequestServiceError.serverError {
            // Also acceptable - server responded with error status
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}

extension RequestServiceError: Equatable {
    public static func == (lhs: RequestServiceError, rhs: RequestServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyMessage, .emptyMessage):
            return true
        case (.encodingFailed, .encodingFailed):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.networkError, .networkError):
            return true // Can't compare underlying errors easily
        default:
            return false
        }
    }
}
