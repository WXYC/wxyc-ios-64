//
//  OnTourForYouSeedDebugState.swift
//  DebugPanel
//
//  Observable singleton for exercising the On Tour "For You" shelf in a debug
//  build without real likes or a live backend enrichment. Replaces the old silent
//  auto-seed (which faked an "In your likes" card whenever the listener had no
//  id-bearing likes) with explicit, opt-in switches the tester turns on and off.
//
//  Holds primitives only — the shelf-building code in the app target reads these
//  and does the `LikedArtist` / station-cap work, so DebugPanel keeps no
//  dependency on the Concerts package.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Shared debug state for the On Tour For You recommendation shelf.
///
/// Lets a tester force the loved tier and the station-affinity tier on so their
/// cards render before real likes or the backend `similar_artists` enrichment
/// exist, without touching production data or the PostHog flag.
@MainActor
@Observable
public final class OnTourForYouSeedDebugState {
    public static let shared = OnTourForYouSeedDebugState()

    /// When true, the shelf seeds a synthetic "loved" like from the first upcoming
    /// show with a resolved headliner, so the loved-tier card renders. Opt-in and
    /// clearly dismissible — never the silent auto-fabrication it replaces.
    public var seedLovedEnabled: Bool {
        didSet { UserDefaults.standard.set(seedLovedEnabled, forKey: Self.seedKey) }
    }

    /// Runtime-only (never persisted): forces the loved seed on for a single launch,
    /// used by the dismiss UI test's `-uiTestResetForYou`. Kept separate from
    /// ``seedLovedEnabled`` on purpose — persisting the toggle from a test would
    /// leave a developer's simulator with a silent seeded card stuck on after the
    /// test exits, the exact failure this whole change removes. Mirrors
    /// ``OnTourShowsDebugState``'s runtime-only `firstPlaycutID`.
    public var seedForcedForTesting = false

    /// Local override for the station-affinity tier cap. `0` defers to the PostHog
    /// flag; a positive value forces the station tier on so its "Heavy rotation"
    /// cards can be previewed without changing the remote flag.
    public var stationCapOverride: Int {
        didSet { UserDefaults.standard.set(stationCapOverride, forKey: Self.stationCapKey) }
    }

    private static let seedKey = "OnTourForYouSeedDebug.seedLoved"
    private static let stationCapKey = "OnTourForYouSeedDebug.stationCapOverride"

    private init() {
        self.seedLovedEnabled = UserDefaults.standard.bool(forKey: Self.seedKey)
        self.stationCapOverride = UserDefaults.standard.integer(forKey: Self.stationCapKey)
    }
}
