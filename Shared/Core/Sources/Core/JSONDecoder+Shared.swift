//
//  JSONDecoder+Shared.swift
//  Core
//
//  Provides a shared default-configured JSONDecoder instance to avoid redundant allocations.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension JSONDecoder {
    /// A shared `JSONDecoder` instance with default configuration.
    ///
    /// Use this instead of creating a new `JSONDecoder()` when no custom configuration
    /// (date strategy, key decoding strategy, etc.) is needed. Because this instance is
    /// never mutated after creation, it is safe for concurrent use across threads.
    ///
    /// - Important: Do not mutate this decoder. If you need custom configuration,
    ///   create a new `JSONDecoder()` instead.
    public static let shared = JSONDecoder()
}
