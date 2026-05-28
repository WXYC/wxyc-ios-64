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
    /// The service had no input to act on and made no network attempt — for example,
    /// `URLArtworkFetcher` called with a playcut whose `artworkURL` is `nil` because
    /// backend metadata enrichment hasn't completed. This is *not* a verdict that the
    /// underlying resource is absent; callers (e.g. `MultisourceArtworkService.scanFetchers`)
    /// must not treat it as a definitive negative result, or a track whose URL arrives
    /// on a later poll will be shadowed by a 30-day "no artwork available" cache entry.
    case notAttempted
}

public protocol WebSession: Sendable {
    func data(from url: URL) async throws -> Data
}
