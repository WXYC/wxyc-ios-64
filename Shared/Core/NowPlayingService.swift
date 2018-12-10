import Foundation

final class NowPlayingService {
    private var cache: Cachable
    private let webSession: WebSession
    
    init(cache: Cachable = Cache.WXYC, webSession: WebSession = URLSession.shared) {
        self.cache = cache
        self.webSession = webSession
    }
    
    func getCurrentPlaycut() -> Future<Playcut> {
        return self.getCachedPlaycut() || self.getRemotePlaycut()
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
    
    private func getRemotePlaycut() -> Future<Playcut> {
        let playlistRequest = webSession.request(url: URL.WXYCPlaylist).transformed { data -> Playlist in
            let decoder = JSONDecoder()
            let playlist = try decoder.decode(Playlist.self, from: data)
            
            return playlist
        }
        
        let playcutRequest = playlistRequest.transformed(with: { playlist -> Playcut in
            guard let playcut = playlist.playcuts.first else {
                throw ServiceErrors.noResults
            }
            
            self.cache[CacheKey.playcut] = playcut
            
            return playcut
        })
        
        return playcutRequest
    }
}

extension URLSession: WebSession {
    func request(url: URL) -> Future<Data> {
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
