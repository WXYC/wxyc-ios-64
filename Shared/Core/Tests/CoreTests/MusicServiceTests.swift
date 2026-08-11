//
//  MusicServiceTests.swift
//  Core
//
//  Tests for the MusicService enum: raw-value contract, Codable round-trip, allCases coverage, display names.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Core

@Suite
struct MusicServiceTests {
    // MARK: - Raw-value contract

    @Test(arguments: [
        (MusicService.appleMusic, "apple_music"),
        (MusicService.spotify, "spotify"),
        (MusicService.bandcamp, "bandcamp"),
        (MusicService.youtubeMusic, "youtube_music"),
        (MusicService.soundcloud, "soundcloud"),
        (MusicService.unknown, "unknown"),
    ])
    func rawValueMapsForward(service: MusicService, rawValue: String) {
        #expect(service.rawValue == rawValue)
    }

    @Test(arguments: [
        ("apple_music", MusicService.appleMusic),
        ("spotify", MusicService.spotify),
        ("bandcamp", MusicService.bandcamp),
        ("youtube_music", MusicService.youtubeMusic),
        ("soundcloud", MusicService.soundcloud),
        ("unknown", MusicService.unknown),
    ])
    func rawValueParsesReverse(rawValue: String, expected: MusicService) {
        #expect(MusicService(rawValue: rawValue) == expected)
    }

    @Test(arguments: ["", "Apple Music", "applemusic", "youtube-music", "not_a_service"])
    func unrecognisedRawValueReturnsNil(rawValue: String) {
        #expect(MusicService(rawValue: rawValue) == nil)
    }

    // MARK: - Codable round-trip

    @Test(arguments: MusicService.allCases)
    func codableRoundTrip(service: MusicService) throws {
        let encoded = try JSONEncoder().encode(service)
        let decoded = try JSONDecoder().decode(MusicService.self, from: encoded)
        #expect(decoded == service)
    }

    @Test(arguments: [
        (MusicService.appleMusic, "\"apple_music\""),
        (MusicService.spotify, "\"spotify\""),
        (MusicService.bandcamp, "\"bandcamp\""),
        (MusicService.youtubeMusic, "\"youtube_music\""),
        (MusicService.soundcloud, "\"soundcloud\""),
        (MusicService.unknown, "\"unknown\""),
    ])
    func codableEmitsRawString(service: MusicService, expectedJSON: String) throws {
        let encoded = try JSONEncoder().encode(service)
        let json = String(data: encoded, encoding: .utf8)
        #expect(json == expectedJSON)
    }

    // MARK: - CaseIterable coverage

    @Test
    func allCasesCoversExactlySixServices() {
        let expected: Set<MusicService> = [.appleMusic, .spotify, .bandcamp, .youtubeMusic, .soundcloud, .unknown]
        #expect(Set(MusicService.allCases) == expected)
        #expect(MusicService.allCases.count == 6)
    }

    // MARK: - Display name

    @Test(arguments: [
        (MusicService.appleMusic, "Apple Music"),
        (MusicService.spotify, "Spotify"),
        (MusicService.bandcamp, "Bandcamp"),
        (MusicService.youtubeMusic, "YouTube Music"),
        (MusicService.soundcloud, "SoundCloud"),
        (MusicService.unknown, "Unknown"),
    ])
    func displayNameMapsCorrectly(service: MusicService, displayName: String) {
        #expect(service.displayName == displayName)
    }

    // MARK: - Host matching (#563)
    //
    // Anchored to the URL *host*, not a substring search — `host == apex ||
    // host.hasSuffix(".\(apex)")` — so a spoofed host that merely contains the
    // apex domain (`spotify.com.evil.example`) is rejected. This is the app-side
    // defense-in-depth guard for StreamingButton: a streaming field's URL is only
    // trusted for a given service when its host is genuinely under that
    // service's apex domain.

    @Test(
        "A URL whose host is genuinely under the service's apex domain matches",
        arguments: [
            (MusicService.spotify, "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"),
            (MusicService.spotify, "https://spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"),
            (MusicService.appleMusic, "https://music.apple.com/us/album/on-your-own-love-again/123"),
            (MusicService.appleMusic, "https://itunes.apple.com/us/album/123"),
            (MusicService.appleMusic, "https://geo.music.apple.com/us/album/123"),
            (MusicService.bandcamp, "https://juanamolina.bandcamp.com/track/la-paradoja"),
            (MusicService.soundcloud, "https://soundcloud.com/chuquimamanicondori/call-your-name"),
            (MusicService.youtubeMusic, "https://www.youtube.com/watch?v=abc123"),
            (MusicService.youtubeMusic, "https://music.youtube.com/watch?v=abc123"),
            (MusicService.youtubeMusic, "https://youtu.be/abc123"),
        ]
    )
    func matchesHostForGenuineServiceURL(service: MusicService, urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(service.matchesHost(of: url))
    }

    @Test(
        "A URL that genuinely belongs to a different service never matches (cross-service mismatch, e.g. Deezer in spotify_url)",
        arguments: [
            (MusicService.spotify, "https://www.deezer.com/album/254381182"),
            (MusicService.spotify, "https://music.apple.com/us/album/on-your-own-love-again/123"),
            (MusicService.appleMusic, "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"),
            (MusicService.bandcamp, "https://soundcloud.com/chuquimamanicondori/call-your-name"),
            (MusicService.soundcloud, "https://juanamolina.bandcamp.com/track/la-paradoja"),
            (MusicService.youtubeMusic, "https://www.deezer.com/album/254381182"),
        ]
    )
    func doesNotMatchAnotherServicesURL(service: MusicService, urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(!service.matchesHost(of: url))
    }

    @Test(
        "A host that merely contains the apex domain as a substring — not a genuine subdomain — never matches (spoof suppression)",
        arguments: [
            (MusicService.spotify, "https://spotify.com.evil.example/track/123"),
            (MusicService.spotify, "https://spotify.company.example/track/123"),
            (MusicService.appleMusic, "https://apple.com.evil.example/album/123"),
            (MusicService.bandcamp, "https://bandcamp.com.evil.example/track/123"),
            (MusicService.soundcloud, "https://soundcloud.com.evil.example/track/123"),
            (MusicService.youtubeMusic, "https://youtube.com.evil.example/watch?v=abc"),
            (MusicService.youtubeMusic, "https://notyoutube.com.evil.test/watch?v=abc"),
        ]
    )
    func doesNotMatchHostSuffixSpoof(service: MusicService, urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(!service.matchesHost(of: url))
    }

    @Test("A nil URL never matches, for every service", arguments: MusicService.allCases)
    func doesNotMatchNilURL(service: MusicService) {
        #expect(!service.matchesHost(of: nil))
    }

    @Test("A hostless URL (e.g. a bare custom-scheme URI) never matches")
    func doesNotMatchHostlessURL() throws {
        let url = try #require(URL(string: "spotify:track:4iV5W9uYEdYUVa79Axb7Rh"))
        #expect(url.host == nil)
        #expect(!MusicService.spotify.matchesHost(of: url))
    }

    @Test("unknown never matches any host, since it declares no apex domains")
    func unknownNeverMatchesAnyHost() throws {
        let url = try #require(URL(string: "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"))
        #expect(!MusicService.unknown.matchesHost(of: url))
    }
}
