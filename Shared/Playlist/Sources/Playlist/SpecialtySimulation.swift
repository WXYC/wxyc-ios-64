//
//  SpecialtySimulation.swift
//  Playlist
//
//  DEBUG-only transform that makes a fetched playlist look like a specialty show is on the air,
//  so every surface derived from `onAir` can be tested without waiting for a real show.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import Foundation
import Synchronization

/// A simulated specialty show. ``apply(to:)`` rewrites a fetched ``Playlist`` so `onAir`,
/// ``Playlist/nowPlayingLead``, ``Playlist/specialtyCard`` and ``Playlist/timelineItems`` all
/// describe the show; nothing is written to the server. The real entries stay underneath.
public struct SpecialtySimulation: Codable, Sendable, Equatable {
    public enum Scenario: String, Codable, Sendable, CaseIterable {
        /// The show just opened: no song of its own yet, so the tagline card shows.
        case justOpened
        /// The show is logging songs: the real playlist's newest song is the show's current song.
        case logging
        /// A show that logs no songs, whatever the program's own flag says.
        case logsNoSongs
        /// A who's-on entry for the show leads.
        case spotlight
    }

    public var isEnabled: Bool
    /// The program from the live catalog. Nothing is simulated until one is chosen.
    public var program: SpecialtyShowRef?
    public var scenario: Scenario
    /// The show's own title for this week (`on_air.show_name`).
    public var title: String?
    public var djHandle: String
    /// The `spotlight` scenario's role (`performer`, `reader`, `dj`, `guest`) and name.
    public var spotlightRole: String
    public var spotlightName: String

    public init(
        isEnabled: Bool = false,
        program: SpecialtyShowRef? = nil,
        scenario: Scenario = .justOpened,
        title: String? = nil,
        djHandle: String = "DJ Sidechain",
        spotlightRole: String = "performer",
        spotlightName: String = "Weirs"
    ) {
        self.isEnabled = isEnabled
        self.program = program
        self.scenario = scenario
        self.title = title
        self.djHandle = djHandle
        self.spotlightRole = spotlightRole
        self.spotlightName = spotlightName
    }

    /// `playlist` with the simulated show on the air; `playlist` itself when off or no program is chosen.
    public func apply(to playlist: Playlist) -> Playlist {
        guard isEnabled, let program else { return playlist }
        let newest = playlist.entries.first
        let newestID = playlist.entries.map(\.id).max() ?? 0
        let newestOrder = playlist.entries.map(\.chronOrderID).max() ?? 0
        let nextShowID = (playlist.entries.compactMap { ($0 as? Playcut)?.showID ?? ($0 as? SpotlightEntry)?.showID }.max() ?? 0) + 1
        // Logging keeps the real newest song in the show, so it leads; every other scenario opens a new show.
        let showID = scenario == .logging ? (playlist.currentPlaycut?.showID ?? nextShowID) : nextShowID
        let hour = newest?.hour ?? 0
        let timeCreated = newest?.timeCreated ?? 0

        let spotlight = scenario == .spotlight ? SpotlightEntry(
            id: newestID + 2, hour: hour, chronOrderID: newestOrder + 2, timeCreated: timeCreated,
            showID: showID, role: spotlightRole, name: spotlightName
        ) : nil
        let simulatedProgram = switch scenario {
        case .logging: program.with(logsPlaycuts: true)
        case .logsNoSongs: program.with(logsPlaycuts: false)
        case .justOpened, .spotlight: program
        }
        let signOn = ShowMarker(
            id: newestID + 1, hour: hour, chronOrderID: newestOrder + 1, timeCreated: timeCreated,
            isStart: true, djName: djHandle, message: "\(djHandle) signed on"
        )
        return Playlist(
            playcuts: playlist.playcuts,
            breakpoints: playlist.breakpoints,
            talksets: playlist.talksets,
            showMarkers: playlist.showMarkers + [signOn],
            onAir: .dj(djHandle, show: OnAirShow(id: showID, title: title, specialty: simulatedProgram, spotlight: spotlight)),
            spotlights: playlist.spotlights + (spotlight.map { [$0] } ?? [])
        )
    }
}

private extension SpecialtyShowRef {
    func with(logsPlaycuts: Bool) -> SpecialtyShowRef {
        SpecialtyShowRef(id: id, slug: slug, name: name, shortName: shortName, tagline: tagline, logsPlaycuts: logsPlaycuts, defaultSpotlightRole: defaultSpotlightRole, artwork: artwork, accentColor: accentColor)
    }
}

/// Holds the one active ``SpecialtySimulation`` and persists it to `UserDefaults`, so it survives a
/// relaunch. ``PlaylistFetcher`` applies ``shared`` to every successful fetch.
public final class SpecialtySimulationStore: @unchecked Sendable {
    public static let shared = SpecialtySimulationStore()
    private static let key = "SpecialtySimulation.v1"

    private let defaults: UserDefaults
    private let current: Mutex<SpecialtySimulation?>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = Mutex(defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SpecialtySimulation.self, from: $0) })
    }

    /// The simulation to apply; `nil` clears it and its saved copy.
    public var simulation: SpecialtySimulation? {
        get { current.withLock { $0 } }
        set {
            current.withLock { $0 = newValue }
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key)
        }
    }

    /// `playlist` simulated by the current setting, or unchanged when none applies.
    public func apply(to playlist: Playlist) -> Playlist {
        simulation?.apply(to: playlist) ?? playlist
    }
}
#endif
