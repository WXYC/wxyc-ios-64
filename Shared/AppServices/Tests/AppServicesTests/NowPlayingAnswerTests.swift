//
//  NowPlayingAnswerTests.swift
//  AppServices
//
//  The one-shot "what's playing" answer the Siri/Shortcuts intent speaks. It must
//  come back promptly when no song leads, where iterating NowPlayingService waits.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Artwork
import PlaylistTesting
@testable import Playlist
@testable import AppServices
@testable import Caching

private let openShow = OnAir.dj("Cat Power Hour", show: OnAirShow(id: 42, title: nil, specialty: nil))
private let hogwash = SpecialtyShowRef(
    id: 3, slug: "hogwash", name: "Hogwash", shortName: nil, tagline: nil,
    logsPlaycuts: false, defaultSpotlightRole: nil, artwork: nil, accentColor: nil
)

struct NowPlayingAnswerCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playlist: Playlist
    let expectedDialog: String
    var testDescription: String { name }
}

private let answerCases: [NowPlayingAnswerCase] = [
    NowPlayingAnswerCase(
        name: "automation answers nothing playing",
        playlist: .stub(playcuts: [.stub(id: 1, showID: 42)], onAir: .automation),
        expectedDialog: "Nothing is playing on WXYC right now."
    ),
    NowPlayingAnswerCase(
        name: "new freeform show with no song answers with the DJ",
        playlist: .stub(playcuts: [.stub(id: 1, showID: 41)], onAir: openShow),
        expectedDialog: "Cat Power Hour is on the air on WXYC."
    ),
    NowPlayingAnswerCase(
        name: "new specialty show with no song answers with the show",
        playlist: .stub(
            playcuts: [.stub(id: 1, showID: 41)],
            onAir: .dj("DJ MONSTER", show: OnAirShow(id: 42, title: nil, specialty: hogwash))
        ),
        expectedDialog: "Hogwash is on the air on WXYC."
    ),
    NowPlayingAnswerCase(
        name: "a song of the open show answers with the song",
        playlist: .stub(
            playcuts: [.stub(id: 1, showID: 42, songTitle: "Back, Baby", artistName: "Jessica Pratt")],
            onAir: openShow
        ),
        expectedDialog: "Back, Baby by Jessica Pratt is now playing on WXYC."
    ),
]

@MainActor
@Suite("NowPlayingService current answer")
struct NowPlayingAnswerTests {
    @Test("answers promptly even when no song leads", .timeLimit(.minutes(1)), arguments: answerCases)
    func answersPromptly(_ testCase: NowPlayingAnswerCase) async {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = testCase.playlist
        let playlistService = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache())
        )
        let service = NowPlayingService(playlistService: playlistService, artworkService: MockArtworkService())

        let answer = await service.currentAnswer(timeout: .seconds(30))

        #expect(answer.spokenDialog == testCase.expectedDialog)
    }

    @Test("times out to unavailable, spoken as can't reach, when no playlist arrives", .timeLimit(.minutes(1)))
    func timesOutWithoutPlaylist() async {
        // The fetcher returns nothing and the cache is empty, so no playlist is ever broadcast.
        let playlistService = PlaylistService(
            fetcher: MockPlaylistFetcher(), interval: 3600,
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache())
        )
        let service = NowPlayingService(playlistService: playlistService, artworkService: MockArtworkService())

        let answer = await service.currentAnswer(timeout: .milliseconds(200))

        #expect(answer == .unavailable)
        #expect(answer.spokenDialog == "Can't reach WXYC right now. Try again in a moment.")
    }
}
