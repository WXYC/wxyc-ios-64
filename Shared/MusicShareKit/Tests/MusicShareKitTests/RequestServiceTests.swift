//
//  RequestServiceTests.swift
//  MusicShareKit
//
//  Tests for RequestService song request behavior.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Testing
@testable import MusicShareKit

@Suite("RequestService Tests")
struct RequestServiceTests {

    init() {
        // Configure MusicShareKit before running tests
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            analyticsService: MockStructuredAnalytics()
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
    }
    
    @Test("sendRequest hits the configured URL")
    func sendRequestUsesConfiguredURL() async throws {
        let session = MockRequestSession()
        let service = RequestService(session: session)

        try await service.sendRequest(message: "la paradoja by Juana Molina")

        let recordedURL = try #require(await session.lastRequest?.url)
        #expect(recordedURL.absoluteString == "https://example.com/request")
        #expect(await session.invocationCount == 1)
    }
}

/// In-memory `RequestSession` that records the last request and returns a 200 response.
private actor MockRequestSession: RequestSession {
    var lastRequest: URLRequest?
    var invocationCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        invocationCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
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
