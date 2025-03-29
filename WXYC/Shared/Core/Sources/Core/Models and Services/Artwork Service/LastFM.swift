import UIKit

struct LastFM {
    private init() { }
    
    struct SearchResponse: Codable {
        let album: Album
    }
    
    struct Album: Codable {
        struct AlbumArt: Codable {
            enum Size: String, Codable, Comparable, CaseIterable {
                case unknown = ""
                case small
                case medium
                case large
                case extralarge
                case mega
                
                static func <(lhs: Size, rhs: Size) -> Bool {
                    let lIndex = self.allCases.firstIndex(of: lhs)!
                    let rIndex = self.allCases.firstIndex(of: rhs)!
                    
                    return lIndex < rIndex
                }
            }
            
            let url: URL
            let size: Size
            
            enum CodingKeys: String, CodingKey {
                case url = "#text"
                case size = "size"
            }
        }
        
        let image: [AlbumArt]
        
        var largestAlbumArt: AlbumArt {
            let allArt = image.sorted { (leftAlbumArt, rightAlbumArt) -> Bool in
                return leftAlbumArt.size < rightAlbumArt.size
            }
            
            return allArt.last!
        }
    }
}

final class LastFMArtworkFetcher: ArtworkFetcher {
    private let session: WebSession
    private let decoder = JSONDecoder()
    
    init(session: WebSession = URLSession.shared) {
        self.session = session
    }
    
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let searchURL = makeSearchURL(for: playcut)
        let searchData = try await session.data(from: searchURL)
        let searchResponse = try decoder.decode(LastFM.SearchResponse.self, from: searchData)
        
        let imageData = try await session.data(from: searchResponse.album.largestAlbumArt.url)
        let image = UIImage(data: imageData)
        
        guard let image = image else {
            throw ServiceError.noResults
        }
        
        return image
    }
    
    private func makeSearchURL(for playcut: Playcut) -> URL {
        let key = "45f85235ffc46cbb8769d545c8059399"
        
        var components = URLComponents(string: "https://ws.audioscrobbler.com")!
        components.path = "/2.0/"
        components.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "method",  value: "album.getInfo"),
            URLQueryItem(name: "artist",  value: playcut.artistName),
            URLQueryItem(name: "album",   value: playcut.releaseTitle),
            URLQueryItem(name: "format",  value: "json")
        ]
        
        return components.url!
    }
}
