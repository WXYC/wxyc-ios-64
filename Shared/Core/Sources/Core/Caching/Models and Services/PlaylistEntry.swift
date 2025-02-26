import Foundation
import Logger

extension URL {
    static let WXYCPlaylist = URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=50")!
    static let WXYCStream128kMP3 = URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc.mp3")!
    static let WXYCStream320kMP3 = URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc-alt.mp3")!
}

public protocol PlaylistEntry: Codable, Identifiable, Sendable {
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
    
    static func ==(lhs: any PlaylistEntry, rhs: any PlaylistEntry) -> Bool {
        lhs.id == rhs.id
    }

    static func !=(lhs: any PlaylistEntry, rhs: any PlaylistEntry) -> Bool {
        !(lhs.id == rhs.id)
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

public struct Playcut: PlaylistEntry {
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
    
    public init(
        id: Int,
        hour: Int,
        chronOrderID: Int,
        songTitle: String,
        labelName: String?,
        artistName: String,
        releaseTitle: String?
    ) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.songTitle = songTitle
        self.labelName = labelName
        self.artistName = artistName
        self.releaseTitle = releaseTitle
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(Int.self, forKey: .id)
        self.hour = try container.decode(Int.self, forKey: .hour)
        self.chronOrderID = try container.decode(Int.self, forKey: .chronOrderID)

        do {
            self.songTitle = try container.decode(String.self, forKey: .songTitle)
            self.labelName = try container.decode(String?.self, forKey: .labelName)
            self.artistName = try container.decode(String.self, forKey: .artistName)
            self.releaseTitle = try container.decode(String?.self, forKey: .releaseTitle)
        } catch {
            Log(.error, "Could not decode Playcut: \(error)")
            throw error
        }
    }
}

public struct Playlist: Codable, Sendable {
    let playcuts: [Playcut]
    let breakpoints: [Breakpoint]
    let talksets: [Talkset]
    
    static let empty = Playlist(playcuts: [], breakpoints: [], talksets: [])
    
    static func ==(lhs: Playlist, rhs: Playlist) -> Bool {
        guard lhs.entries.count == rhs.entries.count else {
            return false
        }
        return zip(lhs.entries.map(\.id), rhs.entries.map(\.id)).allSatisfy(==)
    }

    static func !=(lhs: Playlist, rhs: Playlist) -> Bool {
        !(lhs == rhs)
    }
}

public extension Playlist {
    var entries: [any PlaylistEntry] {
        let playlist: [any PlaylistEntry] = (playcuts + breakpoints + talksets)
        return playlist.sorted { $0.chronOrderID > $1.chronOrderID }
    }
}
