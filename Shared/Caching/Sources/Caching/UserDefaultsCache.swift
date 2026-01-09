import Foundation

struct UserDefaultsCache: Cache {
    private static let metadataSuffix = ".metadata"
    private func userDefaults() -> UserDefaults { .standard }

    func metadata(for key: String) -> CacheMetadata? {
        guard let data = userDefaults().data(forKey: key + Self.metadataSuffix) else {
            return nil
        }
        return try? JSONDecoder().decode(CacheMetadata.self, from: data)
    }

    func data(for key: String) -> Data? {
        userDefaults().data(forKey: key)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        if let data {
            userDefaults().set(data, forKey: key)
            if let metadataData = try? JSONEncoder().encode(metadata) {
                userDefaults().set(metadataData, forKey: key + Self.metadataSuffix)
            }
        } else {
            remove(for: key)
        }
    }

    func remove(for key: String) {
        userDefaults().removeObject(forKey: key)
        userDefaults().removeObject(forKey: key + Self.metadataSuffix)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        // UserDefaultsCache doesn't support iteration for pruning
        []
    }
}

public extension UserDefaults {
    nonisolated(unsafe) static let wxyc = UserDefaults(suiteName: "group.wxyc.iphone")!
}
