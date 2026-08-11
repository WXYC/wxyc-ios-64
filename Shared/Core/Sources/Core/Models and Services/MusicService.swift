//
//  MusicService.swift
//  Core
//
//  Canonical identifier for the music streaming services the app understands.
//  Used by Metadata for streaming-link UI and by MusicShareKit for share-sheet URL parsing.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Identifies a music streaming service.
///
/// The raw `String` values are stable and used for serialization (e.g. analytics payloads,
/// JSON contracts). The `unknown` case is a defensive default for URLs that cannot be
/// attributed to a known service.
public enum MusicService: String, Sendable, CaseIterable, Codable {
    case appleMusic = "apple_music"
    case spotify = "spotify"
    case bandcamp = "bandcamp"
    case youtubeMusic = "youtube_music"
    case soundcloud = "soundcloud"
    case unknown = "unknown"

    /// Human-readable service name suitable for UI labels and donated intent metadata.
    public var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .bandcamp: "Bandcamp"
        case .youtubeMusic: "YouTube Music"
        case .soundcloud: "SoundCloud"
        case .unknown: "Unknown"
        }
    }

    /// Apex (registrable) domains under which this service's canonical URLs live.
    /// Empty for ``unknown`` — no URL host is ever considered a match for it.
    ///
    /// This is a distinct, stricter notion of "ownership" than
    /// `MusicShareKit.MusicServiceProvider.canHandle(url:)`, which matches on
    /// substring containment (deliberately, for share-sheet deep-link
    /// recognition) rather than a suffix-anchored host. See
    /// ``matchesHost(of:)`` for the rationale.
    private var apexHosts: [String] {
        switch self {
        case .appleMusic: ["apple.com"]
        case .spotify: ["spotify.com"]
        case .bandcamp: ["bandcamp.com"]
        case .youtubeMusic: ["youtube.com", "youtu.be"]
        case .soundcloud: ["soundcloud.com"]
        case .unknown: []
        }
    }

    /// Whether `url`'s host is genuinely under one of ``apexHosts`` — either an
    /// exact match or a subdomain (`host == apex || host.hasSuffix(".\(apex)")`),
    /// case-folded.
    ///
    /// A `nil` URL, a URL with no host (e.g. a bare custom-scheme URI), or a
    /// host that merely *contains* the apex domain as a substring
    /// (`spotify.com.evil.example`, `spotify.company.example`) never matches.
    /// This is the host-gate backing `StreamingButton`: a streaming field's URL
    /// is only trusted for a given service when this returns `true` for it —
    /// WXYC/wxyc-ios-64#563.
    public func matchesHost(of url: URL?) -> Bool {
        guard let host = url?.host?.lowercased(), !apexHosts.isEmpty else { return false }
        return apexHosts.contains { apex in
            host == apex || host.hasSuffix(".\(apex)")
        }
    }
}
