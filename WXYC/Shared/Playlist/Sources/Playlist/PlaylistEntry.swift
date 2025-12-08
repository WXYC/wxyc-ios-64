import Foundation
import Logger
import PostHog

extension URL {
    static let WXYCPlaylist = URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=50")!
#if WXYC_320_STREAM_ENABLED
    static let WXYCStream320kMP3 = URL(string: "https://audio-mp3.ibiblio.org:8000/wxyc-alt.mp3")!
#endif
}

public protocol PlaylistEntry: Codable, Identifiable, Sendable, Equatable, Hashable, Comparable {
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
}

public extension PlaylistEntry {
    static func ==(lhs: Self, rhs: any PlaylistEntry) -> Bool {
        lhs.id == rhs.id
    }

    static func !=(lhs: Self, rhs: any PlaylistEntry) -> Bool {
        lhs.id != rhs.id
    }
    
    static func <(lhs: Self, rhs: any PlaylistEntry) -> Bool {
        lhs.chronOrderID < rhs.chronOrderID
    }
    
    static func <(lhs: Self, rhs: Self) -> Bool {
        lhs.chronOrderID < rhs.chronOrderID
    }
    
    static func >(lhs: Self, rhs: any PlaylistEntry) -> Bool {
        rhs.chronOrderID > lhs.chronOrderID
    }
}

public struct Breakpoint: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
    
    
    public var formattedDate: String {
        let timeSince1970 = Double(hour) / 1000.0
        let date = Date(timeIntervalSince1970: timeSince1970)
        
        return Self.dateFormatter.string(from: date)
    }
    
    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h a"
        return dateFormatter
    }()
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
            self.labelName = try container.decodeIfPresent(String.self, forKey: .labelName)
            self.artistName = try container.decode(String.self, forKey: .artistName)
            self.releaseTitle = try container.decodeIfPresent(String.self, forKey: .releaseTitle)
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
    var entries: [any PlaylistEntry] {
        let playlist: [any PlaylistEntry] = (playcuts + breakpoints + talksets)
        return playlist.sorted { $0.chronOrderID > $1.chronOrderID }
    }
}

public extension Playlist {
    static let marketingList = Playlist(
        playcuts: placeholderPlaycuts,
        breakpoints: [],
        talksets: []
    )
    
    private struct PlaceholderSong {
        let songTitle: String
        let artistName: String
        let releaseTitle: String
    }
    
    nonisolated(unsafe) private static var placeholderSongs: [PlaceholderSong] = [
        PlaceholderSong(
            songTitle: "wetdoggs beat",
            artistName: "wetdogg",
            releaseTitle: "pssssssp..."
        ),
        PlaceholderSong(
            songTitle: "Big Shot",
            artistName: "Patric Cowley",
            releaseTitle: "Afternooners"
        ),
        PlaceholderSong(
            songTitle: "The Laarge Daark Aardvark Song",
            artistName: "X-Cetra",
            releaseTitle: "Summer 2000"
        ),
        PlaceholderSong(
            songTitle: "VI Scose Poise",
            artistName: "Autechre",
            releaseTitle: "Confield"
        ),
        PlaceholderSong(
            songTitle: "Come Inside",
            artistName: "The Shades Of Love",
            releaseTitle: "Mr Bongo Record Club, Vol. 7"
        ),
        PlaceholderSong(
            songTitle: "Guinnevere",
            artistName: "Miles Davis",
            releaseTitle: "Bitches Brew"
        ),
        PlaceholderSong(
            songTitle: "Render",
            artistName: "Lyra Pramuk",
            releaseTitle: "Hymna"
        ),
        PlaceholderSong(
            songTitle: "Mevlana (Based On Turkish Religious Melody)",
            artistName: "East New York Ensemble de Music",
            releaseTitle: "At the Helm"
        ),
        PlaceholderSong(
            songTitle: "Bismillahi 'Rrahmani 'Rrahim",
            artistName: "Harold Budd",
            releaseTitle: "Pavilion of Dreams"
        ),
        PlaceholderSong(
            songTitle: "Belleville",
            artistName: "Laurel Halo",
            releaseTitle: "Atlas"
        ),
        PlaceholderSong(
            songTitle: "The Remembering Self",
            artistName: "Barker",
            releaseTitle: "Stochastic Drift"
        ),
        PlaceholderSong(
            songTitle: "Nutrition",
            artistName: "Carmen Villain",
            releaseTitle: "Nutrition EP"
        ),
    ]
    
    private static let placeholderPlaycuts: [Playcut] = placeholderSongs.shuffled().enumerated().map { index, song in
        Playcut(
            id: UInt64(index),
            hour: 0,
            chronOrderID: UInt64(index),
            songTitle: song.songTitle,
            labelName: nil,
            artistName: song.artistName,
            releaseTitle: song.releaseTitle
        )
    }
}

public struct PlaceholderFetcher: PlaylistDataSource {
    public init() { }
    
    public func getPlaylist() async throws -> Playlist {
        Playlist.marketingList
    }
}
