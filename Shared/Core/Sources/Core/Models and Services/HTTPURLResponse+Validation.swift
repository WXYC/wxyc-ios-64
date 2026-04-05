//
//  HTTPURLResponse+Validation.swift
//  Core
//
//  Extension on HTTPURLResponse providing HTTP status code validation for
//  success (2xx) responses, replacing duplicated inline checks across packages.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension HTTPURLResponse {
    /// Validates that the HTTP status code is in the 2xx success range.
    ///
    /// - Throws: `URLError(.badServerResponse)` if the status code is outside
    ///   the 200...299 range.
    public func validateSuccessStatus() throws {
        guard (200...299).contains(statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
