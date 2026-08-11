//
//  MusicServiceProvider.swift
//  MusicShareKit
//
//  Protocol implemented by per-service URL handlers (Apple Music, Spotify, Bandcamp, etc.).
//  Conformers identify whether they own a URL and parse it into a MusicTrack.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import Foundation

public protocol MusicServiceProvider: Sendable {
    var identifier: MusicService { get }

    /// Host fragments this service's web URLs use, e.g. "bandcamp.com".
    ///
    /// Matching is **substring**, not suffix: the default `canHandle` asks
    /// `url.host.lowercased().contains(fragment)`. That is carried over verbatim from the five
    /// per-service `canHandle` bodies this replaced, so it is deliberately no looser and no
    /// tighter than before — but it does mean a hostile host such as
    /// `bandcamp.com.example.invalid` matches. Tightening this to an exact-or-dot-suffix test
    /// would be a behavior change, not a refactor, so it is left alone here; do not read the
    /// list as offering any anti-spoofing guarantee.
    static var hosts: [String] { get }

    /// Custom URL schemes this service also owns, e.g. "spotify" for `spotify://` deep links.
    /// Declared as a requirement (not just an extension default) so a conformer's own value is
    /// actually consulted by the default `canHandle` — a same-named member that only exists in
    /// a protocol extension is statically resolved and silently ignores the conformer's version.
    static var schemes: [String] { get }

    /// Check if this service can handle the given URL
    func canHandle(url: URL) -> Bool

    /// Parse the URL and extract metadata to create a MusicTrack
    func parse(url: URL) -> MusicTrack?

    /// Fetch artwork URL for the track (async)
    func fetchArtwork(for track: MusicTrack) async throws -> URL?

    /// Fetch full metadata for the track (async). Returns updated track with title, artist, album, and artwork.
    /// Default implementation returns the original track unchanged.
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack
}

extension MusicServiceProvider {
    /// Default: no scheme-based deep links. Conformers that need one override it.
    public static var schemes: [String] { [] }

    /// True when the URL's host contains any of `hosts`, or its scheme is one of `schemes`.
    ///
    /// Factored out of `canHandle` so a conformer that needs an *extra* condition can add it on
    /// top of the declarative match instead of re-implementing it. `YouTubeMusicService` is the
    /// one such conformer today. A `canHandle` override cannot reach the protocol extension's
    /// default — there is no `super` for protocol extensions, and calling `canHandle` again
    /// dispatches straight back to the override — so without this helper the only way to extend
    /// the default is to copy it, which then silently stops tracking changes to it (including
    /// the `schemes` branch).
    func matchesDeclaredHostOrScheme(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if Self.hosts.contains(where: { host.contains($0) }) {
            return true
        }

        guard !Self.schemes.isEmpty else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        return Self.schemes.contains(scheme)
    }

    /// Default implementation matches when the URL's host contains any of `hosts`, or
    /// (for services that declare one) the URL's scheme is one of `schemes`.
    public func canHandle(url: URL) -> Bool {
        matchesDeclaredHostOrScheme(url: url)
    }

    /// Default implementation returns the track unchanged
    public func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        return track
    }

    /// Default implementation returns the track's cached artwork URL.
    /// Every conformer fetches artwork as part of `fetchMetadata`, so by the time
    /// `fetchArtwork` is called there is nothing left to do but hand back the cached value.
    public func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        track.artworkURL
    }
}
