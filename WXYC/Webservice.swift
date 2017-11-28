import UIKit

enum Result<T> {
    case success(T)
    case error(Error)
}

public enum ServiceErrors: Error {
    case noResults
}

final class Webservice {
    func getCurrentPlaycut() -> Future<Playcut> {
        return getPlaylist().chained(with: { playlist in
            return Promise(value: playlist.playcuts.first)
        })
    }
    
    private func getPlaylist() -> Future<Playlist> {
        return URLSession.shared.request(url: URL.WXYCPlaylist).transformed { data -> Playlist in
            let decoder = JSONDecoder()
            return try decoder.decode(Playlist.self, from: data)
        }
    }
}

extension Future where Value == Playcut {
    func getArtwork() -> Future<UIImage> {
        let promise = Promise<UIImage>()
        
        let lastFMArtworkRequest = getLastFMArtwork()
        let iTunesArtworkRequest = getItunesArtwork()

        lastFMArtworkRequest.observe { imageResult in
            switch imageResult {
            case let .success(image):
                promise.resolve(with: image)
            case .error(_):
                iTunesArtworkRequest.observe(with: { imageResult in
                    switch imageResult {
                    case let .success(image):
                        promise.resolve(with: image)
                    case .error(_):
                        promise.resolve(with: #imageLiteral(resourceName: "logo"))
                    }
                })
            }
        }
        
        return promise
    }
    
    private func getLastFMArtwork() -> Future<UIImage> {
        return chained(with: { playcut -> Future<UIImage> in
            return playcut.getLastFMAlbum().getAlbumArtwork()
        })
    }
    
    private func getLowResLastFMArtwork() -> Future<UIImage> {
        return chained(with: { playcut -> Future<UIImage> in
            return playcut.getLastFMAlbum().getLowResAlbumArtwork()
        })
    }
    
    private func getItunesArtwork() -> Future<UIImage> {
        return chained(with: { playcut -> Future<UIImage> in
            return playcut.getItunesItem().getAlbumArtwork()
        })
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
    private func getAlbumArtwork() -> Future<UIImage> {
        return chained(with: { album -> Future<UIImage> in
            return album.embiggenAlbumArtURL().getImage()
        })
    }
    
    private func getLowResAlbumArtwork() -> Future<UIImage> {
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
