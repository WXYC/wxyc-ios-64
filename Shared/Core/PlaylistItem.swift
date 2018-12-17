import Foundation

extension URL {
    static var WXYCPlaylist: URL {
        return URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=15")!
    }
    
    static var WXYCStream: URL {
        return URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc.mp3")!
    }
}

public protocol PlaylistItem: Codable {
    var id: Int { get }
    var hour: Int { get }
    var chronOrderID: Int { get }
}

public struct Playcut: PlaylistItem {
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
