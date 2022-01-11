import Foundation

extension URL {
    static let WXYCPlaylist = URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=50")!
    static let WXYCStream = URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc.mp3")!
}

public protocol PlaylistEntry: Codable {
    var id: Int { get }
    var hour: Int { get }
    var chronOrderID: Int { get }
}

public extension PlaylistEntry {
    var debugDescription: String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        
        let decoder = JSONDecoder()
        let dictionary = try! decoder.decode(String.self, from: data)
        return dictionary.debugDescription
    }
}

public struct Breakpoint: PlaylistEntry {
    public let id: Int
    public let hour: Int
    public let chronOrderID: Int
}

public struct Talkset: PlaylistEntry {
    public let id: Int
    public let hour: Int
    public let chronOrderID: Int
}

public struct Playcut: PlaylistEntry, Identifiable, Codable {
    public let id: Int
    public let hour: Int
    public let chronOrderID: Int

    public let songTitle: String
    public let labelName: String?
    public let artistName: String
    public let releaseTitle: String?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case hour
        case chronOrderID
        case songTitle
        case labelName
        case artistName
        case releaseTitle
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(Int.self, forKey: .id)
        self.hour = try container.decode(Int.self, forKey: .hour)
        self.chronOrderID = try container.decode(Int.self, forKey: .chronOrderID)

        self.songTitle = try container.decode(String.self, forKey: .songTitle)
        self.labelName = try container.decode(String?.self, forKey: .labelName)
        self.artistName = try container.decode(String.self, forKey: .artistName)
        self.releaseTitle = try? container.decode(String?.self, forKey: .releaseTitle)
    }
}

public struct Playlist: Codable {
    let playcuts: [Playcut]
    let breakpoints: [Breakpoint]
    let talksets: [Talkset]
    
    static var empty = Playlist(playcuts: [], breakpoints: [], talksets: [])
}

public extension Playlist {
    var entries: [PlaylistEntry] {
        let playlist: [PlaylistEntry] = (playcuts + breakpoints + talksets)
        return playlist.sorted { $0.chronOrderID > $1.chronOrderID }
    }
}
