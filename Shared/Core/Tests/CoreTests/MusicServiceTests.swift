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
}
