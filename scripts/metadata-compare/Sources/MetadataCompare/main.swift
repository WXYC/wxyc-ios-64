//
//  main.swift
//  MetadataCompare
//
//  Fetches the live WXYC playlist via both the v1 (tubafrenzy + on-demand
//  PlaycutMetadataService lookup) and v2 (BS /flowsheet with inline metadata)
//  paths used by the iOS app, then emits a side-by-side per-playcut JSON
//  comparison to a file so we can audit accuracy of each path.
//
//  The fetchers here intentionally bypass PlaylistDataSourceV1 /
//  PlaylistDataSourceV2 because those classes hardcode the endpoint URLs and
//  default windows. We need adjustable -n to drive both endpoints to the same
//  window. The decoded representations are kept equivalent in shape to what
//  the iOS app would build (an iOS-package `Playcut` for v1, the same fields
//  inline on each v2 entry).
//
//  Created by Jake Bromberg on 05/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Metadata
import Playlist

// MARK: - Anonymous auth

/// Minimal SessionTokenProvider that mirrors AuthenticationService's
/// anonymous-sign-in + JWT-exchange flow. No Keychain, no Analytics — for
/// CLI use only.
final class AnonymousTokenProvider: SessionTokenProvider, @unchecked Sendable {
    private let session: URLSession
    private let baseURL: String
    private var cachedJWT: String?
    private let lock = NSLock()

    init(baseURL: String = "https://api.wxyc.org", session: URLSession = .init(configuration: .ephemeral)) {
        self.baseURL = baseURL
        self.session = session
    }

    func token() async throws -> String {
        if let cached = (lock.withLock { cachedJWT }) {
            return cached
        }
        let sessionToken = try await signInAnonymously()
        let jwt = try await fetchJWT(sessionToken: sessionToken)
        lock.withLock { cachedJWT = jwt }
        return jwt
    }

    private func signInAnonymously() async throws -> String {
        let url = URL(string: "\(baseURL)/auth/sign-in/anonymous")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(baseURL, forHTTPHeaderField: "Origin")
        let (data, response) = try await session.data(for: request)
        try assertOK(response, body: data, context: "sign-in/anonymous")
        struct R: Decodable { let token: String }
        return try JSONDecoder().decode(R.self, from: data).token
    }

    private func fetchJWT(sessionToken: String) async throws -> String {
        let url = URL(string: "\(baseURL)/auth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(baseURL, forHTTPHeaderField: "Origin")
        request.addValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try assertOK(response, body: data, context: "auth/token")
        struct R: Decodable { let token: String }
        return try JSONDecoder().decode(R.self, from: data).token
    }

    private func assertOK(_ response: URLResponse, body: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else { throw CLIError.message("\(context): non-HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: body.prefix(500), encoding: .utf8) ?? ""
            throw CLIError.message("\(context): HTTP \(http.statusCode) — \(snippet)")
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let s) = self { s } else { "CLI error" } }
}

// MARK: - V1 (tubafrenzy) fetcher

/// Subset of the tubafrenzy `recentEntries` payload we need.
struct V1Playcut: Decodable {
    let id: UInt64
    let hour: UInt64
    let chronOrderID: UInt64
    let songTitle: String
    let artistName: String
    let releaseTitle: String?
    let labelName: String?
}

struct V1Playlist: Decodable {
    let playcuts: [V1Playcut]
}

func fetchV1Playcuts(n: Int) async throws -> [V1Playcut] {
    let url = URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=\(n)")!
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: URLRequest(url: url))
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw CLIError.message("v1 fetch failed: \(response)")
    }
    return try JSONDecoder().decode(V1Playlist.self, from: data).playcuts
}

// MARK: - V2 (BS /flowsheet) fetcher

/// Mirrors the v2 FlowsheetEntry's wire shape, including all metadata fields
/// the iOS FlowsheetConverter cares about.
struct V2Entry: Decodable {
    let id: Int
    let entry_type: String?
    let artist_name: String?
    let track_title: String?
    let album_title: String?
    let record_label: String?
    let add_time: String
    let release_year: Int?
    let artwork_url: String?
    let discogs_url: String?
    let spotify_url: String?
    let apple_music_url: String?
    let youtube_music_url: String?
    let bandcamp_url: String?
    let soundcloud_url: String?
    let artist_bio: String?
    let artist_wikipedia_url: String?
}

struct V2FlowsheetResponse: Decodable {
    let entries: [V2Entry]
}

func fetchV2Entries(n: Int, token: String) async throws -> [V2Entry] {
    let url = URL(string: "https://api.wxyc.org/flowsheet?limit=\(n)")!
    var request = URLRequest(url: url)
    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw CLIError.message("v2 fetch failed: \(response)")
    }
    return try JSONDecoder().decode(V2FlowsheetResponse.self, from: data).entries
}

// MARK: - Output models

/// Join key for matching v1 and v2 entries.
///
/// Deliberately limited to artist + song. Including release/label in the key
/// breaks legitimate matches because v1 and v2 frequently disagree on those
/// fields (label drift is the headline finding) — every such disagreement
/// would otherwise show as paired "v1-only" / "v2-only" entries that are
/// really the same playcut.
struct TrackKey: Codable, Hashable {
    let artist: String
    let song: String
}

/// Normalized metadata shape used for both v1 and v2 so we can diff them.
struct ResolvedMetadata: Codable {
    let label: String?
    let releaseYear: Int?
    let discogsURL: String?
    let discogsArtistId: Int?
    let artworkURL: String?
    let spotifyURL: String?
    let appleMusicURL: String?
    let youtubeMusicURL: String?
    let bandcampURL: String?
    let soundcloudURL: String?
    let artistWikipediaURL: String?
    let artistBio: String?
    let artistBioLength: Int?

    init(
        label: String? = nil,
        releaseYear: Int? = nil,
        discogsURL: String? = nil,
        discogsArtistId: Int? = nil,
        artworkURL: String? = nil,
        spotifyURL: String? = nil,
        appleMusicURL: String? = nil,
        youtubeMusicURL: String? = nil,
        bandcampURL: String? = nil,
        soundcloudURL: String? = nil,
        artistWikipediaURL: String? = nil,
        artistBio: String? = nil
    ) {
        self.label = label
        self.releaseYear = releaseYear
        self.discogsURL = discogsURL
        self.discogsArtistId = discogsArtistId
        self.artworkURL = artworkURL
        self.spotifyURL = spotifyURL
        self.appleMusicURL = appleMusicURL
        self.youtubeMusicURL = youtubeMusicURL
        self.bandcampURL = bandcampURL
        self.soundcloudURL = soundcloudURL
        self.artistWikipediaURL = artistWikipediaURL
        self.artistBio = artistBio
        self.artistBioLength = artistBio.map(\.count)
    }
}

struct PerSideRow: Codable {
    let id: UInt64
    let hour: UInt64
    let track: TrackKey
    let resolved: ResolvedMetadata
}

struct ComparisonRow: Codable {
    let track: TrackKey
    let v1ID: UInt64?
    let v2ID: UInt64?
    let v1: ResolvedMetadata?
    let v2: ResolvedMetadata?
    /// Fields where one side has a value and the other doesn't.
    let presenceDiffs: [String]
    /// Fields where both sides have a value but they differ.
    let valueDiffs: [String]
}

struct ComparisonReport: Codable {
    let fetchedAt: String
    let v1Count: Int
    let v2Count: Int
    let matched: Int
    let v1Only: Int
    let v2Only: Int
    /// Aggregate counts across all matched rows.
    let presenceDiffCountByField: [String: Int]
    /// Aggregate counts across all matched rows.
    let valueDiffCountByField: [String: Int]
    let comparisons: [ComparisonRow]
    let v1OnlyRows: [PerSideRow]
    let v2OnlyRows: [PerSideRow]
}

// MARK: - Helpers

func normalize(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
}

extension V1Playcut {
    /// Project a tubafrenzy playcut into the iOS Playcut type so it can be
    /// fed to PlaycutMetadataService (which expects the public Playlist type).
    func toIOSPlaycut() -> Playcut {
        Playcut(
            id: id,
            hour: hour,
            chronOrderID: chronOrderID,
            timeCreated: hour,
            songTitle: songTitle,
            labelName: labelName,
            artistName: artistName,
            releaseTitle: releaseTitle
        )
    }

    var trackKey: TrackKey {
        TrackKey(artist: normalize(artistName), song: normalize(songTitle))
    }
}

extension V2Entry {
    var isPlaycut: Bool { (entry_type ?? "track") == "track" }

    var trackKey: TrackKey {
        TrackKey(artist: normalize(artist_name ?? ""), song: normalize(track_title ?? ""))
    }

    var idAsUInt: UInt64 { UInt64(id) }

    var hourMillis: UInt64 {
        if let d = try? Date(add_time, strategy: .iso8601) {
            return UInt64(d.timeIntervalSince1970 * 1000)
        }
        let f = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let d = try? Date(add_time, strategy: f) {
            return UInt64(d.timeIntervalSince1970 * 1000)
        }
        return 0
    }

    /// Pull the inline metadata exactly as the iOS app receives it.
    var inlineResolved: ResolvedMetadata {
        ResolvedMetadata(
            label: record_label,
            releaseYear: release_year,
            discogsURL: discogs_url,
            discogsArtistId: nil, // not exposed in the v2 wire shape
            artworkURL: artwork_url,
            spotifyURL: spotify_url,
            appleMusicURL: apple_music_url,
            youtubeMusicURL: youtube_music_url,
            bandcampURL: bandcamp_url,
            soundcloudURL: soundcloud_url,
            artistWikipediaURL: artist_wikipedia_url,
            artistBio: artist_bio
        )
    }
}

extension PlaycutMetadata {
    var asResolved: ResolvedMetadata {
        ResolvedMetadata(
            label: album.label,
            releaseYear: album.releaseYear,
            discogsURL: album.discogsURL?.absoluteString,
            discogsArtistId: album.discogsArtistId,
            artworkURL: album.artworkURL?.absoluteString,
            spotifyURL: streaming.spotifyURL?.absoluteString,
            appleMusicURL: streaming.appleMusicURL?.absoluteString,
            youtubeMusicURL: streaming.youtubeMusicURL?.absoluteString,
            bandcampURL: streaming.bandcampURL?.absoluteString,
            soundcloudURL: streaming.soundcloudURL?.absoluteString,
            artistWikipediaURL: artist.wikipediaURL?.absoluteString,
            artistBio: artist.bio
        )
    }
}

/// Splits a per-row comparison into presence drift (one side has a value, the
/// other has nil) vs value drift (both have a value but they disagree). Two
/// nils agree on a field.
func categorize(_ v1: ResolvedMetadata, _ v2: ResolvedMetadata) -> (presence: [String], value: [String]) {
    var presence: [String] = []
    var value: [String] = []
    func check<T: Equatable>(_ name: String, _ a: T?, _ b: T?) {
        switch (a, b) {
        case (nil, nil): break
        case (nil, _?), (_?, nil): presence.append(name)
        case let (a?, b?): if a != b { value.append(name) }
        }
    }
    check("label", v1.label, v2.label)
    check("releaseYear", v1.releaseYear, v2.releaseYear)
    check("discogsURL", v1.discogsURL, v2.discogsURL)
    check("artworkURL", v1.artworkURL, v2.artworkURL)
    check("spotifyURL", v1.spotifyURL, v2.spotifyURL)
    check("appleMusicURL", v1.appleMusicURL, v2.appleMusicURL)
    check("youtubeMusicURL", v1.youtubeMusicURL, v2.youtubeMusicURL)
    check("bandcampURL", v1.bandcampURL, v2.bandcampURL)
    check("soundcloudURL", v1.soundcloudURL, v2.soundcloudURL)
    check("artistWikipediaURL", v1.artistWikipediaURL, v2.artistWikipediaURL)
    check("artistBio", v1.artistBio, v2.artistBio)
    return (presence, value)
}

// MARK: - Driver

@main
struct Tool {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        var outPath = "metadata-compare.json"
        var n = 50
        if let i = args.firstIndex(of: "-o"), i + 1 < args.count { outPath = args[i + 1] }
        if let i = args.firstIndex(of: "-n"), i + 1 < args.count, let v = Int(args[i + 1]) { n = v }

        let stderr = FileHandle.standardError
        func log(_ s: String) { stderr.write(Data("\(s)\n".utf8)) }

        let tokenProvider = AnonymousTokenProvider()
        log("[1/4] obtaining anonymous JWT…")
        let jwt = try await tokenProvider.token()

        log("[2/4] fetching v1 playlist (tubafrenzy ?n=\(n))…")
        let v1Playcuts = try await fetchV1Playcuts(n: n)
        log("       got \(v1Playcuts.count) v1 playcuts")

        log("[3/4] fetching v2 playlist (BS /flowsheet ?limit=\(n))…")
        let v2Entries = (try await fetchV2Entries(n: n, token: jwt)).filter(\.isPlaycut)
        log("       got \(v2Entries.count) v2 playcuts (after filtering non-track entries)")

        log("[4/4] resolving v1 metadata via PlaycutMetadataService (one call per playcut)…")
        let svc = PlaycutMetadataService(tokenProvider: tokenProvider)
        var v1Rows: [PerSideRow] = []
        for (idx, pc) in v1Playcuts.enumerated() {
            let resolved = await svc.fetchMetadata(for: pc.toIOSPlaycut())
            v1Rows.append(PerSideRow(id: pc.id, hour: pc.hour, track: pc.trackKey, resolved: resolved.asResolved))
            if (idx + 1) % 10 == 0 || idx + 1 == v1Playcuts.count {
                log("       resolved \(idx + 1)/\(v1Playcuts.count)")
            }
        }
        let v2Rows: [PerSideRow] = v2Entries.map { e in
            PerSideRow(id: e.idAsUInt, hour: e.hourMillis, track: e.trackKey, resolved: e.inlineResolved)
        }

        // Build per-key indexes (highest hour wins on a re-play)
        var v1ByKey: [TrackKey: PerSideRow] = [:]
        for r in v1Rows {
            if let existing = v1ByKey[r.track], existing.hour >= r.hour { continue }
            v1ByKey[r.track] = r
        }
        var v2ByKey: [TrackKey: PerSideRow] = [:]
        for r in v2Rows {
            if let existing = v2ByKey[r.track], existing.hour >= r.hour { continue }
            v2ByKey[r.track] = r
        }

        var comparisons: [ComparisonRow] = []
        var v1Only: [PerSideRow] = []
        var v2Only: [PerSideRow] = []
        var presenceAgg: [String: Int] = [:]
        var valueAgg: [String: Int] = [:]
        for key in Set(v1ByKey.keys).union(v2ByKey.keys) {
            switch (v1ByKey[key], v2ByKey[key]) {
            case let (v1?, v2?):
                let cats = categorize(v1.resolved, v2.resolved)
                for f in cats.presence { presenceAgg[f, default: 0] += 1 }
                for f in cats.value { valueAgg[f, default: 0] += 1 }
                comparisons.append(ComparisonRow(
                    track: key,
                    v1ID: v1.id, v2ID: v2.id,
                    v1: v1.resolved, v2: v2.resolved,
                    presenceDiffs: cats.presence,
                    valueDiffs: cats.value
                ))
            case let (v1?, nil): v1Only.append(v1)
            case let (nil, v2?): v2Only.append(v2)
            default: break
            }
        }
        comparisons.sort { ($0.v1ID ?? 0) > ($1.v1ID ?? 0) }
        v1Only.sort { $0.id > $1.id }
        v2Only.sort { $0.id > $1.id }

        let report = ComparisonReport(
            fetchedAt: ISO8601DateFormatter().string(from: Date()),
            v1Count: v1Rows.count,
            v2Count: v2Rows.count,
            matched: comparisons.count,
            v1Only: v1Only.count,
            v2Only: v2Only.count,
            presenceDiffCountByField: presenceAgg,
            valueDiffCountByField: valueAgg,
            comparisons: comparisons,
            v1OnlyRows: v1Only,
            v2OnlyRows: v2Only
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        let outURL = URL(fileURLWithPath: outPath)
        try data.write(to: outURL)

        let pdRows = comparisons.filter { !$0.presenceDiffs.isEmpty }.count
        let vdRows = comparisons.filter { !$0.valueDiffs.isEmpty }.count
        log("done. matched=\(comparisons.count) v1Only=\(v1Only.count) v2Only=\(v2Only.count)  presenceDiff rows=\(pdRows)  valueDiff rows=\(vdRows)")
        log("wrote \(data.count) bytes to \(outURL.path)")
    }
}
