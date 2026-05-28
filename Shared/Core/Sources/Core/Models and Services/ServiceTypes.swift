//
//  ServiceTypes.swift
//  Core
//
//  Protocol definitions for web session and network service abstractions.
//
//  Created by Jake Bromberg on 12/17/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

public extension TimeInterval {
    static let oneDay = 60.0 * 60.0 * 24.0
    static let sevenDays = oneDay * 7.0
    static let thirtyDays = oneDay * 30.0
}

/// `NowPlayingService` will throw one of these errors, depending
public enum ServiceError: String, Swift.Error, LocalizedError, Codable {
    case noResults
    case noNewData
    /// The service had no input to act on — e.g. a required field on the request
    /// was `nil` — and made no network call. Distinct from `.noResults`, which is
    /// returned only after a real attempt that found nothing.
    ///
    /// Classifiers that distinguish "tried and failed" from "never tried" must
    /// treat this as the latter, otherwise a later attempt with valid input would
    /// be shadowed by a cached negative entry.
    case notAttempted
}

public protocol WebSession: Sendable {
    func data(from url: URL) async throws -> Data
}
