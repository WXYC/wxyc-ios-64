import UIKit

enum Result<T> {
    case success(T)
    case error(Error)
}

public enum ServiceErrors: Error {
    case noResults
    case noNewData
    case noCachedResult
}

final class Webservice {
    private let cache = Cache.WXYC
    
    // I noticed that after running the app for a while the album artwork would consistently start returning low res
    // images from the iTunes API. As you may have guessed, Last.FM rate limits calls to their APIs. The rule of thumb
    // is no more than 5 calls in 5 minutes from a given IP.
    // The workaround, as I've done here, is to cache the previous result from the WXYC API. If the new result matches,
    // we stop the chain of service calls.
    private var lastFetchedPlaycut: Playcut?
    
    func getCurrentPlaycut() -> Future<Playcut> {
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
                self.cache[Cache.CacheKey.artwork] = nil as UIImage?
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

extension Playcut {
    func getArtwork() -> Future<UIImage> {
        return getCachedArtwork() || getLastFMArtwork() || getItunesArtwork() || getDefaultArtwork()
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

extension Playcut {
    func getItunesItem() -> Future<iTunes.SearchResults.Item> {
        let url = iTunes.searchURL(for: self)
        return URLSession.shared.request(url: url)
            .chained(with: { data -> Promise<iTunes.SearchResults.Item> in
                do {
                    let decoder = JSONDecoder()
                    let results = try decoder.decode(iTunes.SearchResults.self, from: data)
                    
                    if let item = results.results.first {
                        return Promise<iTunes.SearchResults.Item>(value: item)
                    } else {
                        throw ServiceErrors.noResults
                    }
                } catch {
                    let result = Promise<iTunes.SearchResults.Item>()
                    result.reject(with: error)
                    return result
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

extension URL {
    func getImage() -> Future<UIImage> {
        return URLSession.shared.request(url: self)
            .chained(with: { (data) -> Future<UIImage> in
                return Promise(value: UIImage(data: data))
            })
    }
}

extension LastFM.Album {
    func embiggenAlbumArtURL() -> URL {
        return largestAlbumArt.url
    }
}

extension Cache {
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
