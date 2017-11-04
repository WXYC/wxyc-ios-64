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
            public enum Size: String, Codable {
                case small
                case medium
                case large
                case extralarge
                case mega
                case unknown = ""
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
