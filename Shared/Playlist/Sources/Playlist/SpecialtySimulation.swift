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
import Caching

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

    /// Ids at or above this are synthetic: no server flowsheet or show id gets anywhere near
    /// `UInt64.max`, so a simulated row can neither collide with a real one nor stand in for one.
    public static let syntheticIDBase: UInt64 = .max - 1023
    private static let showID: UInt64 = .max
    private static let signOnID: UInt64 = .max - 1
    private static let spotlightID: UInt64 = .max - 2

    /// Whether `id` belongs to a simulated row or show. Watermarks that only ever rise
    /// (``PlaylistService``'s confirmed show id) must skip these.
    public static func isSynthetic(_ id: UInt64) -> Bool { id >= syntheticIDBase }

    /// Why ``Scenario/logging`` cannot lead with a song for `playlist`, or `nil` when it can.
    /// It then falls back to the just-opened layout.
    public static func loggingLimitation(for playlist: Playlist) -> String? {
        guard let newest = playlist.currentPlaycut else { return "Logging songs needs a real song in the playlist; none was fetched, so the card leads instead." }
        guard newest.showID != nil else { return "The newest real song has no show id, so it cannot belong to the simulated show; the card leads instead." }
        return nil
    }

    /// `playlist` with the simulated show on the air; `playlist` itself when off or no program is chosen.
    public func apply(to playlist: Playlist) -> Playlist {
        guard isEnabled, let program else { return playlist }
        let newest = playlist.entries.first
        let newestOrder = playlist.entries.map(\.chronOrderID).max() ?? 0
        // Logging keeps the real newest song in the show, so it leads; every other scenario opens a new show.
        let realShowID = scenario == .logging && Self.loggingLimitation(for: playlist) == nil ? playlist.currentPlaycut?.showID : nil
        let showID = realShowID ?? Self.showID
        let hour = newest?.hour ?? 0
        let timeCreated = newest?.timeCreated ?? 0

        let spotlight = scenario == .spotlight ? SpotlightEntry(
            id: Self.spotlightID, hour: hour, chronOrderID: newestOrder + 2, timeCreated: timeCreated,
            showID: showID, role: spotlightRole, name: spotlightName
        ) : nil
        let simulatedProgram = switch scenario {
        case .logging: program.with(logsPlaycuts: true)
        case .logsNoSongs: program.with(logsPlaycuts: false)
        case .justOpened, .spotlight: program
        }
        let signOn = ShowMarker(
            id: Self.signOnID, hour: hour, chronOrderID: newestOrder + 1, timeCreated: timeCreated,
            isStart: true, djName: djHandle, message: "\(djHandle) signed on"
        )
        var shows = playlist.shows
        shows[showID] = PlaylistShow(id: showID, showName: title, djName: djHandle, specialty: simulatedProgram)
        return Playlist(
            playcuts: playlist.playcuts,
            breakpoints: playlist.breakpoints,
            talksets: playlist.talksets,
            showMarkers: playlist.showMarkers + [signOn],
            onAir: .dj(djHandle, show: OnAirShow(id: showID, title: title, specialty: simulatedProgram, spotlight: spotlight)),
            spotlights: playlist.spotlights + (spotlight.map { [$0] } ?? []),
            shows: shows
        )
    }
}

private extension SpecialtyShowRef {
    func with(logsPlaycuts: Bool) -> SpecialtyShowRef {
        SpecialtyShowRef(id: id, slug: slug, name: name, shortName: shortName, tagline: tagline, logsPlaycuts: logsPlaycuts, defaultSpotlightRole: defaultSpotlightRole, artwork: artwork, accentColor: accentColor)
    }
}

/// Holds the one active ``SpecialtySimulation`` and persists it to `defaults`, which in the app is
/// the shared app-group suite so the app, the widget and intents all read the same setting.
/// Reads go to `defaults` every time, so a change made in one process reaches a long-lived
/// extension process too. ``PlaylistFetcher`` applies ``shared`` unless it is given another store.
public final class SpecialtySimulationStore: @unchecked Sendable {
    public static let shared = SpecialtySimulationStore()
    private static let key = "SpecialtySimulation.v1"

    private let defaults: UserDefaults
    private let note = Mutex<String?>(nil)

    public init(defaults: UserDefaults = .wxyc) {
        self.defaults = defaults
    }

    /// The simulation to apply; `nil` clears it and its saved copy.
    public var simulation: SpecialtySimulation? {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SpecialtySimulation.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key) }
    }

    /// Why the last applied simulation could not do exactly what was asked, for the debug sheet.
    public var statusNote: String? { note.withLock { $0 } }

    /// `playlist` simulated by the current setting, or unchanged when none applies.
    public func apply(to playlist: Playlist) -> Playlist {
        guard let simulation else {
            note.withLock { $0 = nil }
            return playlist
        }
        let limitation = simulation.isEnabled && simulation.program != nil && simulation.scenario == .logging
            ? SpecialtySimulation.loggingLimitation(for: playlist) : nil
        note.withLock { $0 = limitation }
        return simulation.apply(to: playlist)
    }

    /// Drops the shared playlist cache entry, so the widget and a cold launch refetch (and so
    /// see the simulation as it now is) rather than serve the old one for up to 15 minutes.
    /// Call it whenever the simulation turns on, off or changes.
    public func invalidatePlaylistCache(in coordinator: CacheCoordinator = .Playlist) async {
        await coordinator.set(value: Playlist?.none, for: PlaylistCacheKey.playlist, lifespan: 0)
    }
}
#endif
