import Foundation

struct iTunes {
    private init() { }
    
    struct SearchResults: Codable {
        let results: [Item]
        
        struct Item: Codable {
            let artistName: String
            let trackName: String
            let artworkUrl100: URL
        }
    }
    
    static func searchURL(`for` playcut: Playcut) -> URL {
        var components = URLComponents(string: "http://itunes.apple.com")!
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: playcut.artistName + " " + playcut.songTitle),
            URLQueryItem(name: "entity", value: "song")
        ]
        
        return components.url!
    }
}
