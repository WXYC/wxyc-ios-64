//
//  NowPlayingInfoCenterManagerTests.swift
//  WXYC
//
//  Unit tests for NowPlayingInfoCenterManager.
//  These tests verify that now playing info is correctly
//  propagated to MPNowPlayingInfoCenter.
//
//  Created by Jake Bromberg on 12/29/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import MediaPlayer
import UIKit
@testable import WXYC
@testable import Playlist
@testable import AppServices
import Artwork

// MARK: - Mock NowPlayingInfoCenter

/// Mock implementation of NowPlayingInfoCenterProtocol for testing.
@MainActor
final class MockNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {
    var nowPlayingInfo: [String: Any]?
    var playbackState: MPNowPlayingPlaybackState = .unknown
}

/// Spy that counts reads of the `nowPlayingInfo` getter.
///
/// Reading `MPNowPlayingInfoCenter.nowPlayingInfo` is a synchronous cross-process
/// (XPC) round-trip to `mediaserverd` that can block the main thread for seconds
/// under contention (Sentry IOS-3P AppHang). `NowPlayingInfoCenterManager` must
/// therefore never read the getter on the main thread; it compares against a local
/// cache instead. `storedInfo` exposes the last value written through the setter so
/// tests can assert on the result without inflating `getterReadCount`.
@MainActor
final class GetterCountingNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {
    private(set) var getterReadCount = 0
    private(set) var setterWriteCount = 0
    /// The last value written through the setter, readable without counting a getter read.
    private(set) var storedInfo: [String: Any]?

    var nowPlayingInfo: [String: Any]? {
        get {
            getterReadCount += 1
            return storedInfo
        }
        set {
            setterWriteCount += 1
            storedInfo = newValue
        }
    }

    var playbackState: MPNowPlayingPlaybackState = .unknown
}
    
// MARK: - Test Helpers

private func makePlaycut(
    id: UInt64 = 1,
    songTitle: String = "Test Song",
    artistName: String = "Test Artist",
    releaseTitle: String? = "Test Album"
) -> Playcut {
    Playcut(
        id: id,
        hour: 0,
        chronOrderID: id,
        timeCreated: 0,
        songTitle: songTitle,
        labelName: nil,
        artistName: artistName,
        releaseTitle: releaseTitle
    )
}

private func makeNowPlayingItem(
    id: UInt64 = 1,
    songTitle: String = "Test Song",
    artistName: String = "Test Artist",
    releaseTitle: String? = "Test Album",
    artwork: UIImage? = nil
) -> NowPlayingItem {
    NowPlayingItem(
        playcut: makePlaycut(
            id: id,
            songTitle: songTitle,
            artistName: artistName,
            releaseTitle: releaseTitle
        ),
        artwork: artwork
    )
}

// MARK: - Now Playing Info Tests

@Suite("Now Playing Info Updates")
@MainActor
struct NowPlayingInfoTests {

    @Test("Playcut info is set correctly")
    func playcutInfoSetCorrectly() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        let item = makeNowPlayingItem(
            songTitle: "My Song",
            artistName: "My Artist",
            releaseTitle: "My Album"
        )
        manager.handleNowPlayingItem(item)

        let info = mockInfoCenter.nowPlayingInfo
        #expect(info != nil)
        #expect(info?[MPMediaItemPropertyTitle] as? String == "My Song")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "My Artist")
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "My Album")
    }

    @Test("Artwork is set when provided")
    func artworkIsSetWhenProvided() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )
        
        // Create a simple test image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let testImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }

        let item = makeNowPlayingItem(artwork: testImage)
        manager.handleNowPlayingItem(item)

        let info = mockInfoCenter.nowPlayingInfo
        #expect(info != nil)
        #expect(info?[MPMediaItemPropertyArtwork] != nil)
        #expect(info?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
    }

    @Test("Nil release title is stored as empty string")
    func nilReleaseTitleStoredAsEmptyString() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        let item = makeNowPlayingItem(releaseTitle: nil)
        manager.handleNowPlayingItem(item)

        let info = mockInfoCenter.nowPlayingInfo
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "")
    }

    @Test("Now playing info updates when new playcut arrives")
    func nowPlayingInfoUpdatesOnNewPlaycut() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        // First playcut
        let item1 = makeNowPlayingItem(songTitle: "Song 1", artistName: "Artist 1")
        manager.handleNowPlayingItem(item1)
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Song 1")

        // Second playcut
        let item2 = makeNowPlayingItem(songTitle: "Song 2", artistName: "Artist 2")
        manager.handleNowPlayingItem(item2)
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Song 2")
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtist] as? String == "Artist 2")
    }
}

// MARK: - Lead-driven writer

nonisolated private let hogwash = SpecialtyShowRef(id: 5, slug: "hogwash", name: "Hogwash", shortName: "HOG", accentColor: "#FF8800")
nonisolated private let program = SpecialtyShowRef(
    id: 6, slug: "nse", name: "New Science Experience", shortName: "NSE",
    artwork: .init(squareURL: URL(string: "https://example.com/nse.png")), accentColor: "#2255AA"
)

nonisolated private func leadPlaylist(onAir: OnAir, songs: [Playcut] = []) -> Playlist {
    Playlist(playcuts: songs, breakpoints: [], talksets: [], onAir: onAir)
}

nonisolated private func song(showID: UInt64?) -> Playcut {
    Playcut(
        id: 10, hour: 0, chronOrderID: 10, timeCreated: 0, showID: showID,
        songTitle: "la paradoja", labelName: nil, artistName: "Juana Molina", releaseTitle: "DOGA"
    )
}

struct LeadCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playlist: Playlist
    let title: String?
    let artist: String?
    let album: String?
    var testDescription: String { name }
}

nonisolated private let weirs = SpotlightEntry(
    id: 11, hour: 0, chronOrderID: 20, timeCreated: 0, showID: 42, role: "performer", name: "Weirs"
)

nonisolated private let leadCases: [LeadCase] = [
    LeadCase(
        name: "a song from the open show",
        playlist: leadPlaylist(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil)), songs: [song(showID: 42)]),
        title: "la paradoja", artist: "Juana Molina", album: "DOGA"
    ),
    LeadCase(
        name: "a who's-on entry on a specialty show: program over the person",
        playlist: leadPlaylist(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: hogwash, spotlight: weirs))),
        title: "Hogwash", artist: "Weirs", album: "WXYC 89.3 FM"
    ),
    LeadCase(
        name: "a who's-on entry on a freeform show: role line over the handle",
        playlist: leadPlaylist(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: weirs))),
        title: "Live in the studio: Weirs", artist: "DJ Sidechain", album: "WXYC 89.3 FM"
    ),
    LeadCase(
        name: "no song yet, specialty show: program over the DJ handle",
        playlist: leadPlaylist(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: hogwash))),
        title: "Hogwash", artist: "DJ Sidechain", album: "WXYC 89.3 FM"
    ),
    LeadCase(
        name: "no song yet, freeform show: the handle over the station",
        playlist: leadPlaylist(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil))),
        title: "DJ Sidechain", artist: "WXYC 89.3 FM", album: "WXYC 89.3 FM"
    ),
    LeadCase(
        name: "the previous show's song never names a new show",
        playlist: leadPlaylist(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil)), songs: [song(showID: 41)]),
        title: "DJ Sidechain", artist: "WXYC 89.3 FM", album: "WXYC 89.3 FM"
    ),
    LeadCase(
        name: "automation leads with nothing",
        playlist: leadPlaylist(onAir: .automation, songs: [song(showID: 41)]),
        title: nil, artist: nil, album: nil
    ),
]

@Suite("Now Playing info follows the lead")
@MainActor
struct NowPlayingLeadWriterTests {
    private func makeManager(
        logo: @escaping @Sendable (SpecialtyShowRef) async -> CGImage? = { _ in nil }
    ) -> (NowPlayingInfoCenterManager, MockNowPlayingInfoCenter) {
        let infoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(infoCenter: infoCenter, boundsSize: CGSize(width: 100, height: 100), programLogo: logo)
        return (manager, infoCenter)
    }

    @Test("title, artist and album for every lead", arguments: leadCases)
    func strings(_ testCase: LeadCase) async {
        let (manager, infoCenter) = makeManager()
        // A song from the previous show is on the lock screen first, as after a show change.
        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Back, Baby", artistName: "Jessica Pratt"))

        await manager.handleLead(of: testCase.playlist) { NowPlayingItem(playcut: $0, artwork: nil) }

        let info = infoCenter.nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == testCase.title)
        #expect(info?[MPMediaItemPropertyArtist] as? String == testCase.artist)
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == testCase.album)
        #expect((info?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork) == (testCase.title != nil))
    }

    @Test("a who's-on entry is cleared by the next song, and a song by automation")
    func leavingALeadClearsIt() async {
        let (manager, infoCenter) = makeManager()
        let open = OnAirShow(id: 42, title: nil, specialty: nil, spotlight: weirs)
        let fetch: @MainActor (Playcut) async -> NowPlayingItem = { NowPlayingItem(playcut: $0, artwork: nil) }

        await manager.handleLead(of: leadPlaylist(onAir: .dj("DJ Sidechain", show: open)), songItem: fetch)
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Live in the studio: Weirs")

        let later = Playcut(id: 30, hour: 0, chronOrderID: 30, timeCreated: 0, showID: 42, songTitle: "Back, Baby", labelName: nil, artistName: "Jessica Pratt", releaseTitle: nil)
        await manager.handleLead(of: leadPlaylist(onAir: .dj("DJ Sidechain", show: open), songs: [later]), songItem: fetch)
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Back, Baby")

        await manager.handleLead(of: leadPlaylist(onAir: .automation), songItem: fetch)
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] == nil)
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil)
    }

    @Test("the program tile is rendered square at the in-app tile size and a high scale, so its text is legible and sharp")
    func tileImageGeometry() throws {
        let image = try #require(NowPlayingInfoCenterManager.tileImage(for: program))

        #expect(image.size == CGSize(width: 72, height: 72))
        #expect(image.scale == 6)
        #expect(image.cgImage?.width == 432)
        #expect(image.cgImage?.height == 432)
    }

    @Test("the tile has the same geometry whatever bounds the artwork is requested at")
    func tileImageIgnoresBounds() async throws {
        let onAir = OnAir.dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: program))
        let infoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(infoCenter: infoCenter, boundsSize: CGSize(width: 440, height: 440), programLogo: { _ in nil })

        await manager.handleLead(of: leadPlaylist(onAir: onAir)) { NowPlayingItem(playcut: $0, artwork: nil) }

        let artwork = try #require(infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
        let image = try #require(artwork.image(at: CGSize(width: 440, height: 440)))
        #expect(image.cgImage?.width == 432)
        #expect(image.cgImage?.height == 432)
    }

    @Test("a program with no logo writes the rendered text tile at once; one with a logo swaps it in")
    func programArtwork() async throws {
        let onAir = OnAir.dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: program))
        let playlist = leadPlaylist(onAir: onAir)
        let fetch: @MainActor (Playcut) async -> NowPlayingItem = { NowPlayingItem(playcut: $0, artwork: nil) }

        let tileOnly = makeManager { _ in nil }
        await tileOnly.0.handleLead(of: playlist, songItem: fetch)
        let tile = try #require(tileOnly.1.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)

        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let logo = try #require(context.makeImage())
        let withLogo = makeManager { _ in logo }
        await withLogo.0.handleLead(of: playlist, songItem: fetch)
        let logoArtwork = try #require(withLogo.1.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)

        let tileImage = try #require(tile.image(at: CGSize(width: 100, height: 100)))
        let logoImage = try #require(logoArtwork.image(at: CGSize(width: 100, height: 100)))
        #expect(tileImage.pngData() != logoImage.pngData())

        let station = makeManager()
        await station.0.handleLead(of: leadPlaylist(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil))), songItem: fetch)
        let stationArtwork = try #require(station.1.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
        let stationImage = try #require(stationArtwork.image(at: CGSize(width: 100, height: 100)))
        #expect(tileImage.pngData() != stationImage.pngData(), "the program's tile, not the station artwork")
    }
}

// MARK: - Getter Avoidance Tests (IOS-3P)

/// Regression coverage for Sentry IOS-3P: an AppHang (>=2s, main thread) whose
/// culprit was `MPNowPlayingInfoCenter.nowPlayingInfo.getter` — a synchronous XPC
/// round-trip to `mediaserverd`. The manager must never read that getter on the
/// main thread; it compares against a locally cached copy of what it last set.
@Suite("Now Playing getter avoidance (IOS-3P)")
@MainActor
struct NowPlayingGetterAvoidanceTests {

    @Test("handleNowPlayingItem never reads the nowPlayingInfo getter but still sets info")
    func handleNowPlayingItemAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Song 1", artistName: "Artist 1"))

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPMediaItemPropertyTitle] as? String == "Song 1")
        #expect(spy.storedInfo?[MPMediaItemPropertyArtist] as? String == "Artist 1")
    }

    @Test("handleNowPlayingItem commits metadata and artwork in a single info-center write")
    func handleNowPlayingItemCommitsOnce() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Song 1", artistName: "Artist 1"))

        // Setting MPNowPlayingInfoCenter.nowPlayingInfo is a synchronous XPC round-trip;
        // metadata and artwork must land in one assignment, not two.
        #expect(spy.setterWriteCount == 1)
        #expect(spy.storedInfo?[MPMediaItemPropertyTitle] as? String == "Song 1")
        #expect(spy.storedInfo?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
    }

    @Test("Repeated handleNowPlayingItem calls never read the getter")
    func repeatedHandleAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Song 1"))
        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Song 2"))

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPMediaItemPropertyTitle] as? String == "Song 2")
    }

    @Test("setPlaybackState never reads the getter")
    func setPlaybackStateAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.setPlaybackState(isPlaying: true)

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
    }

    @Test("updatePlaybackPosition never reads the getter")
    func updatePlaybackPositionAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.updatePlaybackPosition(secondsBehindLive: 30, maxLookback: 300)

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == false)
        #expect(spy.storedInfo?[MPMediaItemPropertyPlaybackDuration] as? Double == 300)
    }

    @Test("clearPlaybackPosition never reads the getter")
    func clearPlaybackPositionAvoidsGetter() {
        let spy = GetterCountingNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: spy,
            boundsSize: CGSize(width: 100, height: 100)
        )

        // Establish some position first, then clear it.
        manager.updatePlaybackPosition(secondsBehindLive: 30, maxLookback: 300)
        manager.clearPlaybackPosition()

        #expect(spy.getterReadCount == 0)
        #expect(spy.storedInfo?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(spy.storedInfo?[MPMediaItemPropertyPlaybackDuration] == nil)
        #expect(spy.storedInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] == nil)
    }
}

// MARK: - Playback State Tests

@Suite("Playback State Updates")
@MainActor
struct NowPlayingPlaybackStateTests {

    @Test(
        "setPlaybackState writes rate and state",
        arguments: [
            (isPlaying: true, expectedRate: 1.0, expectedState: MPNowPlayingPlaybackState.playing),
            (isPlaying: false, expectedRate: 0.0, expectedState: MPNowPlayingPlaybackState.paused),
        ]
    )
    func setPlaybackStateWritesRateAndState(
        isPlaying: Bool,
        expectedRate: Double,
        expectedState: MPNowPlayingPlaybackState
    ) {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.setPlaybackState(isPlaying: isPlaying)

        #expect(mockInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == expectedRate)
        #expect(mockInfoCenter.playbackState == expectedState)
    }

    @Test("Playback state survives subsequent track update")
    func playbackStateSurvivesTrackUpdate() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: CGSize(width: 100, height: 100)
        )

        manager.setPlaybackState(isPlaying: true)
        manager.handleNowPlayingItem(makeNowPlayingItem(songTitle: "Next Song"))

        #expect(mockInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
        #expect(mockInfoCenter.playbackState == .playing)
        #expect(mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Next Song")
    }
}

// MARK: - Integration Tests

@Suite("Integration Tests")
@MainActor
struct NowPlayingIntegrationTests {

    @Test("BoundsSize is used for artwork")
    func boundsSizeUsedForArtwork() {
        let mockInfoCenter = MockNowPlayingInfoCenter()
        let customBoundsSize = CGSize(width: 200, height: 200)

        let manager = NowPlayingInfoCenterManager(
            infoCenter: mockInfoCenter,
            boundsSize: customBoundsSize
        )

        let item = makeNowPlayingItem()
        manager.handleNowPlayingItem(item)

        guard let artwork = mockInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork else {
            Issue.record("Expected artwork to be set")
            return
        }

        #expect(artwork.bounds.size == customBoundsSize)
    }
}
