//
//  RequestServiceTests.swift
//  RequestService
//
//  Created by Jake Bromberg on 11/25/25.
//

import Testing
@testable import RequestService

@Suite("RequestService Tests")
struct RequestServiceTests {
    
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

