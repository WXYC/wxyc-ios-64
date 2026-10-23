//
//  NowPlayingAnswerTests.swift
//  AppServices
//
//  Tests for NowPlayingService.currentAnswer(timeout:): the one prompt, bounded answer to
//  "what's playing" that the Siri/Shortcuts intent speaks, and the copy for each answer.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Artwork
import CoreGraphics
import LoggerTesting
import PlaylistTesting
@testable import Playlist
@testable import AppServices

private let hogwash = SpecialtyShowRef(
    id: 3,
    slug: "hogwash",
    name: "Hogwash",
    shortName: nil,
    tagline: "Weird and wonderful",
    logsPlaycuts: false,
    defaultSpotlightRole: nil,
    artwork: nil,
    accentColor: nil
)

private let leadingSong = Playcut.stub(id: 10, showID: 42, songTitle: "la paradoja", artistName: "Juana Molina")

/// A fetcher whose fetch never completes on its own; cancelled, it fails the way `PlaylistFetcher` does.
private struct HangingPlaylistFetcher: PlaylistFetcherProtocol {
    func fetchPlaylist() async -> Playlist {
        .empty
    }

    func fetchPlaylistResult() async -> Result<Playlist, any Error> {
        do {
            try await Task.sleep(for: .seconds(60))
            return .success(.empty)
        } catch {
            return .failure(error)
        }
    }
}

/// An artwork service whose fetch never completes on its own; it ends only when its task is cancelled.
private struct HangingArtworkService: ArtworkService {
    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
}

/// An artwork service shaped like `MultisourceArtworkService`: the fetch runs in an unstructured task and
/// the caller awaits its value, so cancelling the caller does not stop the fetch. It takes 3 seconds.
private struct UncancellableArtworkService: ArtworkService {
    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        let task = Task<CGImage?, Never> {
            try? await Task.sleep(for: .seconds(3))
            return nil
        }
        _ = await task.value
        throw CancellationError()
    }
}

/// A fetcher that ignores cancellation, as an unstructured fetch does. It takes 3 seconds.
private struct UncancellablePlaylistFetcher: PlaylistFetcherProtocol {
    func fetchPlaylist() async -> Playlist {
        .empty
    }

    func fetchPlaylistResult() async -> Result<Playlist, any Error> {
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(3)) }
        await task.value
        return .success(.empty)
    }
}

/// The artwork services that outlast the timeout: one that honors cancellation, one that does not.
enum SlowArtwork: CaseIterable, Sendable, CustomTestStringConvertible {
    case honorsCancellation
    case ignoresCancellation

    var service: any ArtworkService {
        switch self {
        case .honorsCancellation: HangingArtworkService()
        case .ignoresCancellation: UncancellableArtworkService()
        }
    }

    var testDescription: String {
        switch self {
        case .honorsCancellation: "honors cancellation"
        case .ignoresCancellation: "ignores cancellation"
        }
    }
}

struct AnswerCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playlist: Playlist
    let expectedDialog: String
    var testDescription: String { name }
}

private let answerCases: [AnswerCase] = [
    AnswerCase(
        name: "a leading song",
        playlist: .stub(playcuts: [leadingSong], onAir: .dj("Cat Power Hour", show: OnAirShow(id: 42, title: nil, specialty: nil))),
        expectedDialog: "la paradoja by Juana Molina is now playing on WXYC."
    ),
    AnswerCase(
        name: "a specialty card",
        playlist: .stub(playcuts: [], onAir: .dj("DJ MONSTER", show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: hogwash))),
        expectedDialog: "Hogwash is on the air on WXYC. Weird and wonderful"
    ),
    AnswerCase(
        name: "a DJ handle",
        playlist: .stub(playcuts: [], onAir: .dj("Cat Power Hour", show: OnAirShow(id: 42, title: nil, specialty: nil))),
        expectedDialog: "Cat Power Hour is on the air on WXYC."
    ),
    AnswerCase(
        name: "a who's-on entry newer than the song",
        playlist: .stub(
            playcuts: [leadingSong],
            onAir: .dj("Cat Power Hour", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: .stub(id: 11, role: "performer", name: "Weirs")))
        ),
        expectedDialog: "Live in the studio: Weirs on WXYC."
    ),
    AnswerCase(
        name: "a who's-on entry on a show with no song yet",
        playlist: .stub(
            playcuts: [],
            onAir: .dj("DJ MONSTER", show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: hogwash, spotlight: .stub(id: 11, role: "guest", name: "Ana Lucía Ríos")))
        ),
        expectedDialog: "In the studio: Ana Lucía Ríos on WXYC."
    ),
    AnswerCase(
        name: "a who's-on entry older than the song",
        playlist: .stub(
            playcuts: [leadingSong],
            onAir: .dj("Cat Power Hour", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: .stub(id: 3, role: "performer", name: "Weirs")))
        ),
        expectedDialog: "la paradoja by Juana Molina is now playing on WXYC."
    ),
    AnswerCase(
        name: "nothing leading",
        playlist: .stub(playcuts: [leadingSong], onAir: .automation),
        expectedDialog: "Nothing is playing on WXYC right now."
    ),
]

@Suite("NowPlayingAnswer Tests")
struct NowPlayingAnswerTests {
    private func makeService(
        fetcher: any PlaylistFetcherProtocol,
        artworkService: any ArtworkService = MockArtworkService(),
        errorReporter: MockErrorReporter = MockErrorReporter()
    ) -> NowPlayingService {
        NowPlayingService(
            playlistService: PlaylistService(fetcher: fetcher, cacheCoordinator: makeNowPlayingTestCacheCoordinator()),
            artworkService: artworkService,
            errorReporter: errorReporter
        )
    }

    @Test("answers from the lead rule", arguments: answerCases)
    func answersFromLead(_ testCase: AnswerCase) async {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = testCase.playlist
        let errorReporter = MockErrorReporter()
        let service = makeService(fetcher: fetcher, errorReporter: errorReporter)

        let answer = await service.currentAnswer(timeout: .seconds(30))

        #expect(answer.spokenDialog == testCase.expectedDialog)
        #expect(errorReporter.allReportedErrors.isEmpty)
    }

    @Test("a leading song carries its playcut and artwork")
    func songCarriesArtwork() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = answerCases[0].playlist
        let service = makeService(fetcher: fetcher)

        let answer = await service.currentAnswer(timeout: .seconds(30))

        guard case .song(let item) = answer else {
            Issue.record("Expected a song, got \(answer)")
            return
        }
        #expect(item.playcut == leadingSong)
        #expect(item.artwork != nil)
    }

    /// The Siri intent used to await the service's iterator, which skips every playlist a who's-on entry
    /// leads, so it hung through a live set. `currentAnswer` fetches once, so it must answer at once.
    @Test("a who's-on entry leading answers promptly with that entry, not a timeout")
    func spotlightLeadAnswersPromptly() async {
        let weirs = SpotlightEntry.stub(id: 11, role: "performer", name: "Weirs")
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(
            playcuts: [leadingSong],
            onAir: .dj("Cat Power Hour", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: weirs))
        )
        let errorReporter = MockErrorReporter()
        let service = makeService(fetcher: fetcher, errorReporter: errorReporter)
        let clock = ContinuousClock()

        var answer: NowPlayingAnswer?
        let elapsed = await clock.measure {
            answer = await service.currentAnswer(timeout: .seconds(30))
        }

        #expect(answer == .spotlight(line: "Live in the studio: Weirs"))
        #expect(elapsed < .seconds(5))
        #expect(errorReporter.allReportedErrors.isEmpty)
    }

    @Test("a failed fetch answers unavailable well within the timeout and does not report again")
    func failedFetchAnswersUnavailablePromptly() async {
        let fetcher = MockPlaylistFetcher()
        fetcher.errorToThrow = URLError(.notConnectedToInternet)
        let errorReporter = MockErrorReporter()
        let service = makeService(fetcher: fetcher, errorReporter: errorReporter)
        let clock = ContinuousClock()

        var answer: NowPlayingAnswer?
        let elapsed = await clock.measure {
            answer = await service.currentAnswer(timeout: .seconds(30))
        }

        #expect(answer == .unavailable)
        #expect(elapsed < .seconds(5))
        // PlaylistFetcher reports a failed fetch itself; the mock does not, so any report here is a duplicate.
        #expect(errorReporter.allReportedErrors.isEmpty)
    }

    @Test("a failed fetch is never spoken as nothing playing")
    func failedFetchIsNotNothing() async {
        let fetcher = MockPlaylistFetcher()
        fetcher.errorToThrow = URLError(.timedOut)
        let service = makeService(fetcher: fetcher)

        let answer = await service.currentAnswer(timeout: .seconds(30))

        #expect(answer != .nothing)
        #expect(answer.spokenDialog == "Can't reach WXYC right now. Try again in a moment.")
    }

    @Test("a playlist fetch that outlasts the timeout answers unavailable and reports")
    func playlistTimeoutAnswersUnavailable() async {
        let errorReporter = MockErrorReporter()
        let service = makeService(fetcher: HangingPlaylistFetcher(), errorReporter: errorReporter)

        let answer = await service.currentAnswer(timeout: .milliseconds(100))

        #expect(answer == .unavailable)
        #expect(errorReporter.allReportedErrors.count == 1)
    }

    @Test("a slow artwork fetch answers the known song without artwork, within the timeout, and does not report", arguments: SlowArtwork.allCases)
    func slowArtworkAnswersSongWithoutArtwork(_ slowArtwork: SlowArtwork) async {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = answerCases[0].playlist
        let errorReporter = MockErrorReporter()
        let service = makeService(fetcher: fetcher, artworkService: slowArtwork.service, errorReporter: errorReporter)
        let clock = ContinuousClock()

        var answer: NowPlayingAnswer?
        let elapsed = await clock.measure {
            answer = await service.currentAnswer(timeout: .milliseconds(100))
        }

        #expect(answer == .song(NowPlayingItem(playcut: leadingSong, artwork: nil)))
        #expect(elapsed < .seconds(2))
        #expect(errorReporter.allReportedErrors.isEmpty)
    }

    @Test("a playlist fetch that ignores cancellation still answers unavailable within the timeout and reports once")
    func uncancellablePlaylistFetchIsBounded() async {
        let errorReporter = MockErrorReporter()
        let service = makeService(fetcher: UncancellablePlaylistFetcher(), errorReporter: errorReporter)
        let clock = ContinuousClock()

        var answer: NowPlayingAnswer?
        let elapsed = await clock.measure {
            answer = await service.currentAnswer(timeout: .milliseconds(100))
        }

        #expect(answer == .unavailable)
        #expect(elapsed < .seconds(2))
        #expect(errorReporter.allReportedErrors.count == 1)
    }

    @Test("cancelling the caller answers unavailable promptly and does not report a timeout")
    func cancelledCallerIsNotReportedAsTimeout() async {
        let errorReporter = MockErrorReporter()
        let service = makeService(fetcher: HangingPlaylistFetcher(), errorReporter: errorReporter)
        let clock = ContinuousClock()

        let caller = Task { await service.currentAnswer(timeout: .seconds(30)) }
        try? await Task.sleep(for: .milliseconds(50))
        var answer: NowPlayingAnswer?
        let elapsed = await clock.measure {
            caller.cancel()
            answer = await caller.value
        }

        #expect(answer == .unavailable)
        #expect(elapsed < .seconds(2))
        #expect(errorReporter.allReportedErrors.isEmpty)
    }
}
