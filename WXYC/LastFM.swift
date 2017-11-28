import Foundation

public struct LastFM {
    private init() { }
    
    public enum Errors: Error {
        case noAlbumArt
    }
    
    public struct SearchResponse: Codable {
        let album: Album
    }
    
    public struct Album: Codable {
        public struct AlbumArt: Codable {
            public enum Size: String, Codable, Comparable {
                case small
                case medium
                case large
                case extralarge
                case mega
                case unknown = ""
                
                public static func <(lhs: LastFM.Album.AlbumArt.Size, rhs: LastFM.Album.AlbumArt.Size) -> Bool {
                    let ordering: [Size] = [.unknown, .small, .medium, .large, .extralarge, .mega]
                    
                    guard let lOrdinal = ordering.index(of: lhs), let rOrdinal = ordering.index(of: rhs) else {
                        return false
                    }
                    
                    return lOrdinal < rOrdinal
                }
            }
            
            let url: URL
            let size: Size
            
            enum CodingKeys: String, CodingKey {
                case url = "#text"
                case size = "size"
            }
        }
        
        let name: String
        let artist: String
        let image: [AlbumArt]
        
        var largestAlbumArt: AlbumArt {
            let allArt = image.sorted { (leftAlbumArt, rightAlbumArt) -> Bool in
                return leftAlbumArt.size < rightAlbumArt.size
            }
            
            return allArt.last!
        }
    }
    
    static func searchURL(`for` playcut: Playcut, apiKey: String = apiKey) -> URL {
        var components = URLComponents(string: "http://ws.audioscrobbler.com")!
        components.path = "/2.0/"
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "method",  value: "album.getInfo"),
            URLQueryItem(name: "artist",  value: playcut.artistName),
            URLQueryItem(name: "album",   value: playcut.releaseTitle),
            URLQueryItem(name: "format",  value: "json")
        ]
        
        return components.url!
    }
}
