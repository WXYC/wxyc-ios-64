import UIKit

/// A service request will either succeed with a value or fail with an error, never both.
public enum Result<T> {
    case success(T)
    case error(Error)
    
    func flatten() -> T? {
        guard case .success(let value) = self else {
            return nil
        }
        
        return value
    }
}

/// `NowPlayingService` will throw one of these errors, depending
public enum ServiceErrors: Error {
    case noResults
    case noNewData
    case noCachedResult
}

public protocol WebSession {
    func request(url: URL) -> Future<Data>
}

public protocol Cachable {
    subscript<Key: RawRepresentable, Value: Codable>(_ key: Key) -> Value? where Key.RawValue == String { get set }
}

/// `NowPlayingService` is responsible for retrieving the now playing
public final class NowPlayingService {
    private var cache: Cachable
    private let webSession: WebSession
    
    init(cache: Cachable = Cache.WXYC, webSession: WebSession = URLSession.shared) {
        self.cache = cache
        self.webSession = webSession
    }
    
    public func getCurrentPlaycut() -> Future<Playcut> {
        return self.getCachedPlaycut() || self.getPlaylist().transformed(with: { playlist -> Playcut in
            guard let playcut = playlist.playcuts.first else {
                throw ServiceErrors.noResults
            }

            self.cache[CacheKey.playcut] = playcut
            
            return playcut
        })
    }
    
    private func getCachedPlaycut() -> Future<Playcut> {
        let cachedPlaycutRequest: Future<Playcut> = self.cache.getCachedValue(key: .playcut)
        
        cachedPlaycutRequest.observe { result in
            // We receive an error in the event that the cached record either expired or wasn't there to begin with.
            if case .error(_) = result {
                // We therefore need to evict the cached artwork associated with the playcut.
                self.cache[CacheKey.artwork] = nil as Data?
            }
        }
        
        return cachedPlaycutRequest
    }
    
    private func getPlaylist() -> Future<Playlist> {
        return webSession.request(url: URL.WXYCPlaylist).transformed { data -> Playlist in
            let decoder = JSONDecoder()
            let playlist = try decoder.decode(Playlist.self, from: data)
            
            return playlist
        }
    }
}

extension URLSession: WebSession {
    public func request(url: URL) -> Future<Data> {
        let promise = Promise<Data>()
        
        let task = dataTask(with: url) { data, _, error in
            if let error = error {
                promise.reject(with: error)
            } else {
                promise.resolve(with: data ?? Data())
            }
        }
        
        task.resume()
        
        return promise
    }
}

extension Cache {
    static var WXYC: Cache {
        return Cache(defaults: UserDefaults(suiteName: "org.wxyc.apps")!)
    }
}
