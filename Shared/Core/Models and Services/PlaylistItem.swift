import Foundation

extension URL {
    static let WXYCPlaylist = URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=50")!
    
    static let WXYCStream = URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc.mp3")!
}

public protocol PlaylistItem: Codable {
    var id: Int { get }
    var hour: Int { get }
    var chronOrderID: Int { get }
}

public extension Collection where Element == PlaylistItem {
    static func ==(lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        
        for (l, r) in zip(lhs[\.id], rhs[\.id]) where l != r {
            return false
        }
        
        return true
    }
}

public struct Playcut: PlaylistItem, Hashable {
    public let id: Int
    public let hour: Int
    public let chronOrderID: Int
    public let request: Bool = false
    public let songTitle: String
    public let labelName: String?
    public let artistName: String
    public let releaseTitle: String?
}

public struct Talkset: PlaylistItem {
    public let id: Int
    public let hour: Int
    public let chronOrderID: Int
}

public struct Breakpoint: PlaylistItem {
    public let id: Int
    public let hour: Int
    public let chronOrderID: Int
}

public struct Playlist: Codable {
    let playcuts: [Playcut]
    let talksets: [Talkset]
    let breakpoints: [Breakpoint]
    
    public var playlistItems: [PlaylistItem] {
        var items: [PlaylistItem] = []
        items.append(contentsOf: playcuts)
        items.append(contentsOf: talksets)
        items.append(contentsOf: breakpoints)

        return items.sorted(by: \.chronOrderID, comparator: >)
    }
}

public extension Sequence {
    func sorted<T: Comparable>(by keyPath: KeyPath<Element, T>, comparator: (T, T) -> Bool = { $0 < $1 }) -> [Element] {
        return sorted(by: { (e1, e2) -> Bool in
            return comparator(e1[keyPath: keyPath], e2[keyPath: keyPath])
        })
    }
}
