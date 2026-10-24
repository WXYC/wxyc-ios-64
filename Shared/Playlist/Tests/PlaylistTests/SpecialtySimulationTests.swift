//
//  SpecialtySimulationTests.swift
//  Playlist
//
//  Verifies the DEBUG-only specialty-show simulation: each scenario's effect on `onAir`,
//  `nowPlayingLead` and `specialtyCard`, that "off" is the identity, that it persists, and
//  that the fetcher applies it to a successful fetch only.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import Testing
import Foundation
import LoggerTesting
import AnalyticsTesting
import PlaylistTesting
@testable import Playlist

private let nse = SpecialtyShowRef(id: 7, slug: "new-science-experience", name: "New Science Experience", shortName: "NSE", tagline: "Beats and bleeps", logsPlaycuts: false)
private let ocs = SpecialtyShowRef(id: 1, slug: "orange-county-special", name: "Orange County Special", shortName: "OCS", tagline: "Folk and bluegrass", logsPlaycuts: true)

private let freeformShow = OnAirShow(id: 50, title: nil, specialty: nil)
private let realPlaylist = Playlist.stub(
    playcuts: [Playcut.stub(id: 9, showID: 50), Playcut.stub(id: 10, showID: 50)],
    onAir: .dj("DJ Moo", show: freeformShow)
)

private func simulation(_ program: SpecialtyShowRef, _ scenario: SpecialtySimulation.Scenario, title: String? = nil) -> SpecialtySimulation {
    SpecialtySimulation(isEnabled: true, program: program, scenario: scenario, title: title, djHandle: "DJ Sidechain", spotlightRole: "performer", spotlightName: "Weirs")
}

struct SimulationCase: Sendable, CustomTestStringConvertible {
    let name: String
    let simulation: SpecialtySimulation
    let lead: String
    let placement: SpecialtyCard.Placement
    let showsTagline: Bool
    let nowLine: String?
    var testDescription: String { name }
}

private let simulationCases: [SimulationCase] = [
    SimulationCase(name: "just opened: the tagline card leads, over the real songs", simulation: simulation(ocs, .justOpened, title: "Fiddle Night"), lead: "specialtyCard", placement: .aboveSongList, showsTagline: true, nowLine: nil),
    SimulationCase(name: "logging: the real newest song leads under the card", simulation: simulation(nse, .logging), lead: "song", placement: .aboveSongList, showsTagline: false, nowLine: nil),
    SimulationCase(name: "logs no songs: the card is the now-playing item", simulation: simulation(ocs, .logsNoSongs), lead: "specialtyCard", placement: .nowPlaying, showsTagline: true, nowLine: nil),
    SimulationCase(name: "spotlight: the who's-on entry leads", simulation: simulation(ocs, .spotlight), lead: "spotlight", placement: .aboveSongList, showsTagline: false, nowLine: "Live in the studio: Weirs"),
]

private func leadName(_ lead: NowPlayingLead) -> String {
    switch lead {
    case .song: "song"
    case .spotlight: "spotlight"
    case .specialtyCard: "specialtyCard"
    case .djHandle: "djHandle"
    case .nothing: "nothing"
    }
}

@Suite("Specialty Simulation Tests")
struct SpecialtySimulationTests {
    @Test("Each scenario yields the expected lead and card", arguments: simulationCases)
    func scenario(_ testCase: SimulationCase) throws {
        let simulated = testCase.simulation.apply(to: realPlaylist)
        #expect(leadName(simulated.nowPlayingLead) == testCase.lead)
        let card = try #require(simulated.specialtyCard)
        #expect(card.program.slug == testCase.simulation.program?.slug)
        #expect(card.djHandle == "DJ Sidechain")
        #expect(card.placement == testCase.placement)
        #expect(card.showsTagline == testCase.showsTagline)
        #expect(card.nowLine == testCase.nowLine)
        #expect(card.showName == testCase.simulation.title)
        guard case .dj("DJ Sidechain", let show?) = simulated.onAir else {
            Issue.record("expected a named DJ on air")
            return
        }
        #expect(show.specialty?.slug == testCase.simulation.program?.slug)
        #expect(simulated.onAirSignOn?.djName == "DJ Sidechain")
    }

    @Test("Real entries stay underneath the simulated show")
    func keepsRealEntries() {
        let simulated = simulation(ocs, .justOpened).apply(to: realPlaylist)
        #expect(simulated.playcuts == realPlaylist.playcuts)
    }

    @Test("A simulated who's-on entry sorts above every real entry")
    func newestOnTop() {
        let simulated = simulation(ocs, .spotlight).apply(to: realPlaylist)
        #expect(simulated.entries.first is SpotlightEntry)
    }

    @Test("Off is the identity", arguments: [
        SpecialtySimulation(isEnabled: false, program: ocs, scenario: .spotlight),
        SpecialtySimulation(isEnabled: true, program: nil, scenario: .spotlight),
    ])
    func off(_ simulation: SpecialtySimulation) {
        #expect(simulation.apply(to: realPlaylist) == realPlaylist)
    }

    @Test("The store applies nothing until set, and persists what it is given")
    func storePersists() throws {
        let suite = "SpecialtySimulationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SpecialtySimulationStore(defaults: defaults)
        #expect(store.apply(to: realPlaylist) == realPlaylist)

        store.simulation = simulation(ocs, .logging)
        #expect(store.apply(to: realPlaylist) != realPlaylist)
        #expect(SpecialtySimulationStore(defaults: defaults).simulation == simulation(ocs, .logging))
    }
}

@Suite("Specialty Simulation Fetcher Tests", .serialized)
struct SpecialtySimulationFetcherTests {
    private func fetcher(returning playlist: Playlist, error: Error? = nil) -> PlaylistFetcher {
        let dataSource = MockPlaylistDataSource()
        dataSource.playlistToReturn = playlist
        dataSource.errorToThrow = error
        return PlaylistFetcher(dataSource: dataSource, errorReporter: MockErrorReporter(), analytics: MockStructuredAnalytics())
    }

    @Test("A successful fetch is simulated while the shared store is on, and untouched once it is off")
    func appliesToSuccess() async {
        let previous = SpecialtySimulationStore.shared.simulation
        defer { SpecialtySimulationStore.shared.simulation = previous }

        SpecialtySimulationStore.shared.simulation = simulation(ocs, .justOpened)
        let simulated = await fetcher(returning: realPlaylist).fetchPlaylist()
        #expect(simulated.specialtyCard?.program.slug == "orange-county-special")

        SpecialtySimulationStore.shared.simulation = nil
        #expect(await fetcher(returning: realPlaylist).fetchPlaylist() == realPlaylist)
    }

    @Test("A failed fetch stays a failure")
    func failurePassesThrough() async {
        let previous = SpecialtySimulationStore.shared.simulation
        defer { SpecialtySimulationStore.shared.simulation = previous }
        SpecialtySimulationStore.shared.simulation = simulation(ocs, .justOpened)

        let result = await fetcher(returning: .empty, error: URLError(.notConnectedToInternet)).fetchPlaylistResult()
        guard case .failure = result else {
            Issue.record("expected a failure")
            return
        }
    }
}
#endif
