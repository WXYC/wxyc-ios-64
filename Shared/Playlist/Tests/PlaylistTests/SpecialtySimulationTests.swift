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
import Analytics
import AnalyticsTesting
import PlaylistTesting
@testable import Playlist
@testable import Caching

private let beatsAndBleeps = SpecialtyShowRef(id: 7, slug: "beats-and-bleeps", name: "Beats and Bleeps", shortName: "BB", tagline: "Beats and bleeps", logsPlaycuts: false)
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
    SimulationCase(name: "logging: the real newest song leads under the card", simulation: simulation(beatsAndBleeps, .logging), lead: "song", placement: .aboveSongList, showsTagline: false, nowLine: nil),
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

/// A store over its own throwaway defaults suite, so no test touches the app group or the process's saved settings.
private func isolatedStore(_ simulation: SpecialtySimulation? = nil) throws -> (SpecialtySimulationStore, cleanup: @Sendable () -> Void) {
    let suite = "SpecialtySimulationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let store = SpecialtySimulationStore(defaults: defaults)
    store.simulation = simulation
    return (store, { defaults.removePersistentDomain(forName: suite) })
}

@Suite("Specialty Simulation Fetcher Tests")
struct SpecialtySimulationFetcherTests {
    private func fetcher(returning playlist: Playlist, error: Error? = nil, store: SpecialtySimulationStore, analytics: MockStructuredAnalytics = MockStructuredAnalytics()) -> PlaylistFetcher {
        let dataSource = MockPlaylistDataSource()
        dataSource.playlistToReturn = playlist
        dataSource.errorToThrow = error
        return PlaylistFetcher(dataSource: dataSource, errorReporter: MockErrorReporter(), analytics: analytics, simulationStore: store)
    }

    @Test("A successful fetch is simulated while the injected store is on, and untouched once it is off")
    func appliesToSuccess() async throws {
        let (store, cleanup) = try isolatedStore(simulation(ocs, .justOpened))
        defer { cleanup() }
        let simulated = await fetcher(returning: realPlaylist, store: store).fetchPlaylist()
        #expect(simulated.specialtyCard?.program.slug == "orange-county-special")

        store.simulation = nil
        #expect(await fetcher(returning: realPlaylist, store: store).fetchPlaylist() == realPlaylist)
    }

    @Test("A failed fetch stays a failure")
    func failurePassesThrough() async throws {
        let (store, cleanup) = try isolatedStore(simulation(ocs, .justOpened))
        defer { cleanup() }
        let result = await fetcher(returning: .empty, error: URLError(.notConnectedToInternet), store: store).fetchPlaylistResult()
        guard case .failure = result else {
            Issue.record("expected a failure")
            return
        }
    }

    @Test("Analytics sees the real playlist, never the simulated rows")
    func analyticsSeesRealRows() async throws {
        let (store, cleanup) = try isolatedStore(simulation(ocs, .spotlight))
        defer { cleanup() }
        let analytics = MockStructuredAnalytics()
        _ = await fetcher(returning: .empty, store: store, analytics: analytics).fetchPlaylist()
        let events = analytics.events(named: FetchPlaylistEvent.name)
        #expect(events.count == 1)
        #expect(events.first?.properties?["result_count"] as? Int == 0)
    }
}

@Suite("Specialty Simulation Identity Tests")
struct SpecialtySimulationIdentityTests {
    @Test("Synthetic ids never collide with the real rows, whatever the scenario", arguments: SpecialtySimulation.Scenario.allCases)
    func syntheticIDs(_ scenario: SpecialtySimulation.Scenario) {
        let simulated = simulation(ocs, scenario).apply(to: realPlaylist)
        let realIDs = Set(realPlaylist.entries.map(\.id))
        let added = simulated.entries.filter { !realIDs.contains($0.id) }
        #expect(!added.isEmpty)
        #expect(added.allSatisfy { SpecialtySimulation.isSynthetic($0.id) })
        if scenario != .logging, case .dj(_, let show?) = simulated.onAir {
            #expect(SpecialtySimulation.isSynthetic(show.id ?? 0))
        }
    }

    @Test("The simulated show is recorded in shows[] so the scrollback header matches")
    func showsEntry() throws {
        let simulated = simulation(ocs, .justOpened, title: "Fiddle Night").apply(to: realPlaylist)
        guard case .dj(_, let show?) = simulated.onAir, let id = show.id else {
            Issue.record("expected an open show")
            return
        }
        let entry = try #require(simulated.shows[id])
        #expect(entry.showName == "Fiddle Night")
        #expect(entry.specialty?.slug == "orange-county-special")
    }

    @Test("Logging with no songs falls back to the card and says why")
    func loggingWithoutSongs() throws {
        let empty = Playlist.stub(playcuts: [], onAir: .dj("DJ Moo", show: freeformShow))
        let (store, cleanup) = try isolatedStore(simulation(ocs, .logging))
        defer { cleanup() }
        let simulated = store.apply(to: empty)
        #expect(leadName(simulated.nowPlayingLead) == "specialtyCard")
        #expect(store.statusNote != nil)
    }

    @Test("Logging whose newest song has no show id falls back and says why")
    func loggingWithoutShowID() throws {
        let noShow = Playlist.stub(playcuts: [Playcut.stub(id: 9, showID: nil)], onAir: .dj("DJ Moo", show: freeformShow))
        let (store, cleanup) = try isolatedStore(simulation(ocs, .logging))
        defer { cleanup() }
        _ = store.apply(to: noShow)
        #expect(store.statusNote != nil)
        _ = store.apply(to: realPlaylist)
        #expect(store.statusNote == nil)
    }

    @Test("Invalidating drops the cached playlist so readers refetch")
    func invalidatesCache() async throws {
        let (store, cleanup) = try isolatedStore()
        defer { cleanup() }
        let coordinator = CacheCoordinator(cache: InMemoryCache())
        await coordinator.set(value: realPlaylist, for: PlaylistCacheKey.playlist, lifespan: 900)
        await store.invalidatePlaylistCache(in: coordinator)
        let cached: Playlist? = try? await coordinator.value(for: PlaylistCacheKey.playlist)
        #expect(cached == nil)
    }

    @Test("Stopping the simulation leaves the service's show watermark as if it never ran")
    func watermarkUntouched() async throws {
        let cache = CacheCoordinator(cache: InMemoryCache())
        let simulated = simulation(ocs, .justOpened).apply(to: realPlaylist)
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = simulated
        let service = PlaylistService(fetcher: fetcher, interval: 3600, cacheCoordinator: cache)
        _ = await service.fetchAndCachePlaylist()
        fetcher.playlistToReturn = realPlaylist
        _ = await service.fetchAndCachePlaylist()
        #expect(await service.confirmedShowIDForTesting == 50)
    }
}
#endif
