import UIKit

/// A service request will either succeed with a value or fail with an error, never both.
public enum Result<T> {
    case success(T)
    case error(Error)
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

/// `NowPlayingService` is responsible for retrieving the now playing
public final class NowPlayingService {
    private let cache: Cache
    private let webSession: URLSession
    
    public init(cache: Cache = .WXYC, webSession: URLSession = URLSession.shared) {
        self.cache = cache
        self.webSession = webSession
    }
    
    public func getCurrentPlaycut() -> Future<Playcut> {
        return getCachedPlaycut() || getPlaylist().transformed(with: { playlist -> Playcut in
            guard let playcut = playlist.playcuts.first else {
                throw ServiceErrors.noResults
            }

            // Retrieve the playcut from the cache, for later comparison
            let cachedPlaycut: Playcut? = self.cache[Cache.CacheKey.playcut]
            
            // We cache the playcut. It may be that this playcut is already in the cache. That's okay, because what we really
            // want is to reset the timestamp of the cache record
            self.cache[Cache.CacheKey.playcut] = playcut
            
            if playcut == cachedPlaycut {
                throw ServiceErrors.noNewData
            } else {
                return playcut
            }
        })
    }
    
    private func getCachedPlaycut() -> Future<Playcut> {
        let cachedPlaycutRequest: Future<Playcut> = self.cache.getCachedValue(key: Cache.CacheKey.playcut)
        
        cachedPlaycutRequest.observe { result in
            // We receive an error in the event that the cached record either expired or wasn't there to begin with.
            if case .error(_) = result {
                // We therefore need to evict the cached artwork associated with the playcut.
                self.cache[Cache.CacheKey.artwork] = nil as Data?
            }
        }
        
        return cachedPlaycutRequest
    }
    
    private func getPlaylist() -> Future<Playlist> {
        return URLSession.shared.request(url: URL.WXYCPlaylist).transformed { data -> Playlist in
            let decoder = JSONDecoder()
            let playlist = try decoder.decode(Playlist.self, from: data)
            
            return playlist
        }
    }
}

internal extension Playcut {
    func getArtwork() -> Future<UIImage> {
        let request = getCachedArtwork() || getLastFMArtwork() || getItunesArtwork() || getDefaultArtwork()
        request.onSuccess { image in
            Cache.WXYC[Cache.CacheKey.artwork] = UIImagePNGRepresentation(image)
        }
        
        return request
    }
    
    private func getCachedArtwork() -> Future<UIImage> {
        let dataRequest: Future<Data> = Cache.WXYC.getCachedValue(key: Cache.CacheKey.artwork)
        let imageRequest: Future<UIImage> =  dataRequest.transformed(with: UIImage.init)

        return imageRequest
    }
    
    private func getLastFMArtwork() -> Future<UIImage> {
        return getLastFMAlbum().getAlbumArtwork()
    }
    
    private func getLowResLastFMArtwork() -> Future<UIImage> {
        return getLastFMAlbum().getLowResAlbumArtwork()
    }
    
    private func getItunesArtwork() -> Future<UIImage> {
        return getItunesItem().getAlbumArtwork()
    }
    
    private func getDefaultArtwork() -> Future<UIImage> {
        return Promise(value: #imageLiteral(resourceName: "logo"))
    }
}

struct WebRequest<A> {
    let url: URL
    let transform: (Data) throws -> A
}

extension WebRequest where A: Codable {
    init(url: URL) {
        self.url = url
        self.transform = { data in
            let decoder = JSONDecoder()
            return try decoder.decode(A.self, from: data)
        }
    }
}

extension WebRequest {
    static func iTunesItemRequest(for playcut: Playcut) -> WebRequest<iTunes.SearchResults.Item> {
        let url = iTunes.searchURL(for: playcut)
        
        return WebRequest<iTunes.SearchResults.Item>(url: url, transform: { data in
            let decoder = JSONDecoder()
            let results = try decoder.decode(iTunes.SearchResults.self, from: data)
            
            if let item = results.results.first {
                return item
            } else {
                throw ServiceErrors.noResults
            }
        })
    }
}

extension URLSession {
    func getItunesItem(for playcut: Playcut) -> Future<iTunes.SearchResults.Item> {
        let url = iTunes.searchURL(for: playcut)
        return self.request(url: url)
            .transformed(with: { data -> iTunes.SearchResults.Item in
                let decoder = JSONDecoder()
                let results = try decoder.decode(iTunes.SearchResults.self, from: data)
                
                if let item = results.results.first {
                    return item
                } else {
                    throw ServiceErrors.noResults
                }
            })
    }
}

extension Playcut {
    func getItunesItem() -> Future<iTunes.SearchResults.Item> {
        let url = iTunes.searchURL(for: self)
        return URLSession.shared.request(url: url)
            .transformed(with: { data -> iTunes.SearchResults.Item in
                let decoder = JSONDecoder()
                let results = try decoder.decode(iTunes.SearchResults.self, from: data)

                if let item = results.results.first {
                    return item
                } else {
                    throw ServiceErrors.noResults
                }
            })
    }
    
    func getLastFMAlbum() -> Future<LastFM.Album> {
        let lastFMURL = LastFM.searchURL(for: self)
        return URLSession.shared.request(url: lastFMURL)
            .transformed(with: { data -> LastFM.Album in
                let decoder = JSONDecoder()
                let searchResponse = try decoder.decode(LastFM.SearchResponse.self, from: data)
                
                return searchResponse.album
            })
    }
}

extension Future where Value == iTunes.SearchResults.Item {
    func getAlbumArtwork() -> Future<UIImage> {
        return chained(with: { item -> Future<UIImage> in
            return item.artworkUrl100.getImage()
        })
    }
}

extension Future where Value == LastFM.Album {
    fileprivate func getAlbumArtwork() -> Future<UIImage> {
        return chained(with: { album -> Future<UIImage> in
            return album.embiggenAlbumArtURL().getImage()
        })
    }
    
    func getLowResAlbumArtwork() -> Future<UIImage> {
        return chained(with: { album -> Future<UIImage> in
            guard let albumArt = album.image.last else {
                throw LastFM.Errors.noAlbumArt
            }
            
            return albumArt.url.getImage()
        })
    }
}

public extension URL {
    public func getImage() -> Future<UIImage> {
        return URLSession.shared.request(url: self)
            .chained(with: { (data) -> Future<UIImage> in
                return Promise(value: UIImage(data: data))
            })
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

private extension LastFM.Album {
    func embiggenAlbumArtURL() -> URL {
        return largestAlbumArt.url
    }
}

private extension Cache {
    enum CacheKey: String {
        case playcut
        case artwork
    }
    
    func getCachedValue<Value: Codable>(key: CacheKey) -> Future<Value> {
        let promise = Promise<Value>()
        
        if let cachedValue: Value = self[key] {
            promise.resolve(with: cachedValue)
        } else {
            promise.reject(with: ServiceErrors.noCachedResult)
        }
        
        return promise
    }
}

public extension Cache {
    static var WXYC: Cache {
        return Cache(defaults: UserDefaults(suiteName: "org.wxyc.apps")!)
    }
}
