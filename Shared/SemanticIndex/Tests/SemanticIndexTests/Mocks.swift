//
//  Mocks.swift
//  SemanticIndex
//
//  Shared mock objects for SemanticIndex service tests.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core
@testable import Caching

// MARK: - Mock WebSession

final class MockWebSession: WebSession, @unchecked Sendable {
    var responses: [String: Data] = [:]
    var requestedURLs: [URL] = []
    var requestCount = 0

    func data(from url: URL) async throws -> Data {
        requestCount += 1
        requestedURLs.append(url)

        for (pattern, data) in responses {
            if url.absoluteString.contains(pattern) {
                return data
            }
        }

        throw ServiceError.noResults
    }
}

// MARK: - Mock Cache

final class MockCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]
    var getCallCount = 0
    var setCallCount = 0
    var accessedKeys: [String] = []
    var setKeys: [String] = []

    func metadata(for key: String) -> CacheMetadata? {
        getCallCount += 1
        accessedKeys.append(key)
        return metadataStorage[key]
    }

    func data(for key: String) -> Data? {
        dataStorage[key]
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        setCallCount += 1
        setKeys.append(key)
        if let data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            remove(for: key)
        }
    }

    func remove(for key: String) {
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        metadataStorage.map { ($0.key, $0.value) }
    }

    func clearAll() {
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }

    func totalSize() -> Int64 {
        dataStorage.values.reduce(0) { $0 + Int64($1.count) }
    }
}
