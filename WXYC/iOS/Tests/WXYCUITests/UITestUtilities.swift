//
//  UITestUtilities.swift
//  WXYC
//
//  Reusable utilities for UI tests with condition-based waiting.
//
//  Created by Jake Bromberg on 01/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import XCTest

// MARK: - Errors

struct TestTimeoutError: Error {
    let message: String
    init(_ message: String = "Condition not met within timeout") {
        self.message = message
    }
}

// MARK: - Condition-Based Waiting

/// Waits until a condition is met, yielding between checks.
/// Returns immediately when the condition becomes true.
func waitUntil(
    timeout: Duration = .seconds(5),
    _ description: String = "condition",
    condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            throw TestTimeoutError("Timed out waiting for \(description)")
        }
        await Task.yield()
    }
}

/// Waits until an XCUIElement meets the specified requirements.
func waitUntil(
    _ element: XCUIElement,
    is requirements: ElementRequirement...,
    timeout: Duration = .seconds(5)
) async throws {
    try await waitUntil(timeout: timeout, "element \(requirements)") {
        requirements.allSatisfy { req in
            switch req {
            case .exists: element.exists
            case .hittable: element.isHittable
            case .enabled: element.isEnabled
            }
        }
    }
}

// MARK: - Element Requirements

enum ElementRequirement: CustomStringConvertible {
    case exists
    case hittable
    case enabled

    var description: String {
        switch self {
        case .exists: "exists"
        case .hittable: "hittable"
        case .enabled: "enabled"
        }
    }
}
