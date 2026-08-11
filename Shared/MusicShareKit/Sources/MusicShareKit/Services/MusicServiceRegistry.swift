//
//  MusicServiceRegistry.swift
//  MusicShareKit
//
//  Registry of music service handlers for URL matching.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

public final class MusicServiceRegistry: Sendable {
    public static let shared = MusicServiceRegistry()

    private let services: [MusicServiceProvider]

    private init() {
        services = [
            AppleMusicService(),
            SpotifyService(),
            BandcampService(),
            YouTubeMusicService(),
            SoundCloudService()
        ]
    }

    /// The first registered provider that claims `url`, or `nil` if none does.
    ///
    /// - Important: This is **recognition, not verification.** The underlying
    ///   `canHandle(url:)` implementations match the host by substring
    ///   containment, so `spotify.com.evil.example` identifies as Spotify, and
    ///   first-match-wins means an over-matching provider also shadows later
    ///   ones. That is deliberate and adequate for share-sheet deep-link
    ///   routing, where the URL is one the user just shared.
    ///
    ///   Do **not** use this as a trust gate for deciding whether a URL handed
    ///   to the app by the backend genuinely belongs to a service. Use
    ///   `Core.MusicService.matchesHost(of:)`, which is suffix-anchored to the
    ///   service's apex domain. The two predicates differ on purpose — see
    ///   WXYC/wxyc-ios-64#563 — so tightening one is not a reason to collapse
    ///   them into the other.
    public func identifyService(for url: URL) -> MusicServiceProvider? {
        return services.first { $0.canHandle(url: url) }
    }
    
    public func parse(url: URL) -> MusicTrack? {
        guard let service = identifyService(for: url) else {
            return nil
        }
        return service.parse(url: url)
    }
}
