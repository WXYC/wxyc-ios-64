//
//  PlaylistEntry.swift
//  Playlist
//
//  Defines the core playlist data models including Playcut, Breakpoint, Talkset, ShowMarker,
//  and the Playlist container type that aggregates all entry types from the WXYC API.
//
//  Created by Jake Bromberg on 04/16/20.
//  Copyright © 2020 WXYC. All rights reserved.
//

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

/// Represents a show start or end marker from the v2 API.
public struct ShowMarker: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
    public let isStart: Bool
    public let djName: String?
    public let message: String

    public init(
        id: UInt64,
        hour: UInt64,
        chronOrderID: UInt64,
        isStart: Bool,
        djName: String?,
        message: String
    ) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.isStart = isStart
        self.djName = djName
        self.message = message
    }
}

public struct Playcut: PlaylistEntry, Hashable {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64

    public let songTitle: String
    public let labelName: String?
    public let artistName: String
    public let releaseTitle: String?
    
    /// Whether this playcut is a rotation play (station library track).
    /// Rotation plays have their artwork cached longer than non-rotation plays.
    public let rotation: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case hour
        case chronOrderID
        case songTitle
        case labelName
        case artistName
        case releaseTitle
        case rotation
    }

    public init(
        id: UInt64,
        hour: UInt64,
        chronOrderID: UInt64,
        songTitle: String,
        labelName: String?,
        artistName: String,
        releaseTitle: String?,
        rotation: Bool = false
    ) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.songTitle = songTitle
        self.labelName = labelName
        self.artistName = artistName
        self.releaseTitle = releaseTitle
        self.rotation = rotation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UInt64.self, forKey: .id)
        self.hour = try container.decode(UInt64.self, forKey: .hour)
        self.chronOrderID = try container.decode(UInt64.self, forKey: .chronOrderID)

        do {
            self.songTitle = try container.decode(String.self, forKey: .songTitle).htmlDecoded
            self.labelName = try container.decodeIfPresent(String.self, forKey: .labelName)?.htmlDecoded
            self.artistName = try container.decode(String.self, forKey: .artistName).htmlDecoded
            self.releaseTitle = try container.decodeIfPresent(String.self, forKey: .releaseTitle)?.htmlDecoded

            // V1 API returns rotation as a string ("true"/"false"), V2 converter uses Bool
            if let rotationBool = try? container.decodeIfPresent(Bool.self, forKey: .rotation) {
                self.rotation = rotationBool
            } else if let rotationString = try container.decodeIfPresent(String.self, forKey: .rotation) {
                self.rotation = rotationString.lowercased() == "true"
            } else {
                self.rotation = false
            }
        } catch {
            Log(.error, "Could not decode Playcut: \(error)")
            PostHogSDK.shared.capture(error: error, context: "Playcut init")
            throw error
        }
    }
}

public extension Playcut {
    /// Cache key for artwork lookups based on artist and release/song title.
    ///
    /// Uses `releaseTitle` if available and non-empty, otherwise falls back to `songTitle`.
    /// This ensures consistent cache keys regardless of whether `releaseTitle` is `nil` or empty string.
    var artworkCacheKey: String {
        let release = releaseTitle.flatMap { $0.isEmpty ? nil : $0 } ?? songTitle
        return "\(artistName)-\(release)"
    }
}

public struct Playlist: Codable, Sendable {
    public let playcuts: [Playcut]
    let breakpoints: [Breakpoint]
    let talksets: [Talkset]
    public let showMarkers: [ShowMarker]

    public init(
        playcuts: [Playcut],
        breakpoints: [Breakpoint],
        talksets: [Talkset],
        showMarkers: [ShowMarker] = []
    ) {
        self.playcuts = playcuts
        self.breakpoints = breakpoints
        self.talksets = talksets
        self.showMarkers = showMarkers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playcuts = try container.decode([Playcut].self, forKey: .playcuts)
        self.breakpoints = try container.decode([Breakpoint].self, forKey: .breakpoints)
        self.talksets = try container.decode([Talkset].self, forKey: .talksets)
        // showMarkers is optional for backwards compatibility with v1 API
        self.showMarkers = try container.decodeIfPresent([ShowMarker].self, forKey: .showMarkers) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case playcuts, breakpoints, talksets, showMarkers
    }

    public static let empty = Playlist(playcuts: [], breakpoints: [], talksets: [], showMarkers: [])
    
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
        let playlist: [any PlaylistEntry] = (playcuts + breakpoints + talksets + showMarkers)
        return playlist.sorted { $0.chronOrderID > $1.chronOrderID }
    }
}
