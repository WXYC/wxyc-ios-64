//
//  UpcomingShowProvider.swift
//  WXYC
//
//  Supplies the `UpcomingShow` (if any) for a playcut's artist, injected through
//  the environment so `PlaycutDetailView` stays decoupled from the data source.
//  Today the default is a DEBUG-only mock driven by a debug-sheet toggle; when
//  Backend-Service's concerts read API lands, a network-backed provider replaces
//  it with no view changes (see triangle-shows-integration-proposal.md).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Playlist
import SwiftUI
#if DEBUG
import DebugPanel
#endif

/// Resolves the upcoming Triangle-area show for a played track, matched by
/// artist. Async so a real implementation can hit the network / a cache.
protocol UpcomingShowProviding: Sendable {
    func upcomingShow(for playcut: Playcut) async -> Concert?
}

/// The production default until the real provider exists: never surfaces a show.
struct NoUpcomingShowProvider: UpcomingShowProviding {
    func upcomingShow(for playcut: Playcut) async -> Concert? { nil }
}

#if DEBUG
/// Development provider: returns a mock show for the now-playing (first) playcut
/// only while the "Mock ticket on first item" debug toggle is on. Lets the Box
/// Office ticket be exercised end-to-end in the running app without a real
/// upcoming show. Every other playcut resolves to `nil`.
struct DebugMockUpcomingShowProvider: UpcomingShowProviding {
    func upcomingShow(for playcut: Playcut) async -> Concert? {
        await MainActor.run {
            let debug = TouringShowsDebugState.shared
            guard debug.mockFirstItemEnabled, debug.firstPlaycutID == playcut.id else {
                return nil
            }
            return Concert.mock(for: playcut)
        }
    }
}

private extension Concert {
    /// A plausible on-sale show at Cat's Cradle, titled after the played artist so
    /// the mock reads coherently ("Playing Near You" for whoever is on now).
    static func mock(for playcut: Playcut) -> Concert {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let startsOn = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
            ?? Date(timeIntervalSince1970: 1_785_898_800)
        let doorsAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 19))
        let startsAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 20))
        return Concert(
            id: 900_000 + Int(playcut.id % 100_000),
            venue: Venue(id: 3, slug: "cats-cradle", name: "Cat's Cradle", city: "Carrboro", state: "NC", address: nil),
            startsOn: startsOn,
            startsAt: startsAt,
            doorsAt: doorsAt,
            headliningArtistRaw: playcut.artistName,
            supportingArtistsRaw: ["Tapir!"],
            ticketURL: URL(string: "https://www.etix.com/ticket/p/mock"),
            priceMin: 22,
            priceMax: 25,
            ageRestriction: "All Ages",
            status: .onSale
        )
    }
}
#endif

// MARK: - Environment

private struct UpcomingShowProviderKey: EnvironmentKey {
    // A toggle-driven mock in DEBUG so the feature is exercisable now; inert in
    // release until a real, backend-backed provider is injected at the app root.
    static let defaultValue: any UpcomingShowProviding = {
        #if DEBUG
        DebugMockUpcomingShowProvider()
        #else
        NoUpcomingShowProvider()
        #endif
    }()
}

extension EnvironmentValues {
    /// The source of upcoming-show data for playcut detail. Defaults to a DEBUG
    /// mock (toggle-driven) / release no-op.
    var upcomingShowProvider: any UpcomingShowProviding {
        get { self[UpcomingShowProviderKey.self] }
        set { self[UpcomingShowProviderKey.self] = newValue }
    }
}
