import Foundation
import Logger
import PostHog

extension URL {
    static let WXYCPlaylist = URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=50")!
    static let WXYCStream128kMP3 = URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc.mp3")!
    static let WXYCStream320kMP3 = URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc-alt.mp3")!
}

public protocol PlaylistEntry: Codable, Identifiable, Sendable, Equatable, Hashable {
    var id: UInt64 { get }
    var hour: UInt64 { get }
    var chronOrderID: UInt64 { get }
}

public extension PlaylistEntry {
    var debugDescription: String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        
        let decoder = JSONDecoder()
        let dictionary = try! decoder.decode(String.self, from: data)
        return dictionary.debugDescription
    }
    
    var formattedDate: String {
        let timeSince1970 = Double(hour) / 1000.0
        let date = Date(timeIntervalSince1970: timeSince1970)
        
        return dateFormatter.string(from: date)
    }
}

private let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "h a"
    return dateFormatter
}()

public extension PlaylistEntry {
    static func ==(lhs: any PlaylistEntry, rhs: any PlaylistEntry) -> Bool {
        lhs.id == rhs.id
    }

    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    static func !=(lhs: any PlaylistEntry, rhs: any PlaylistEntry) -> Bool {
        !(lhs.id == rhs.id)
    }
    
    static func <(lhs: Self, rhs: any PlaylistEntry) -> Bool {
        lhs.chronOrderID < rhs.chronOrderID
    }
    
    static func >(lhs: Self, rhs: any PlaylistEntry) -> Bool {
        rhs.chronOrderID < lhs.chronOrderID
    }
}

public struct Breakpoint: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
}

public struct Talkset: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
}

public struct Playcut: PlaylistEntry, Hashable {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64

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
        id: UInt64,
        hour: UInt64,
        chronOrderID: UInt64,
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
        
        self.id = try container.decode(UInt64.self, forKey: .id)
        self.hour = try container.decode(UInt64.self, forKey: .hour)
        self.chronOrderID = try container.decode(UInt64.self, forKey: .chronOrderID)

        do {
            self.songTitle = try container.decode(String.self, forKey: .songTitle)
            self.labelName = try container.decode(String?.self, forKey: .labelName)
            self.artistName = try container.decode(String.self, forKey: .artistName)
            self.releaseTitle = try container.decode(String?.self, forKey: .releaseTitle)
        } catch {
            Log(.error, "Could not decode Playcut: \(error)")
            PostHogSDK.shared.capture(error: error, context: "Playcut init")
            throw error
        }
    }
}

public struct Playlist: Codable, Sendable {
    public let playcuts: [Playcut]
    let breakpoints: [Breakpoint]
    let talksets: [Talkset]
    
    public static let empty = Playlist(playcuts: [], breakpoints: [], talksets: [])
    
    public static func ==(lhs: Playlist, rhs: Playlist) -> Bool {
        guard lhs.entries.count == rhs.entries.count else {
            return false
        }
        return zip(lhs.entries.map(\.id), rhs.entries.map(\.id)).allSatisfy(==)
    }

    public static func !=(lhs: Playlist, rhs: Playlist) -> Bool {
        !(lhs == rhs)
    }
}

public extension Playlist {
    enum WrappedEntry: Identifiable {
        public var id: UInt64 {
            switch self {
            case .playcut(let playcut):
                return playcut.id
            case .breakpoint(let breakpoint):
                return breakpoint.id
            case .talkset(let talkset):
                return talkset.id
            }
        }
        
        case playcut(Playcut)
        case breakpoint(Breakpoint)
        case talkset(Talkset)
    }
    
    var entries: [any PlaylistEntry] {
        let playlist: [any PlaylistEntry] = (playcuts + breakpoints + talksets)
        return playlist.sorted { $0.chronOrderID > $1.chronOrderID }
    }
    
    var wrappedEntries: [WrappedEntry] {
        entries.map { entry in
            switch entry {
            case let playcut as Playcut:
                return .playcut(playcut)
            case let breakpoint as Breakpoint:
                return .breakpoint(breakpoint)
            case let talkset as Talkset:
                return .talkset(talkset)
            default:
                fatalError("Unsupported entry type")
            }
        }
    }
}
