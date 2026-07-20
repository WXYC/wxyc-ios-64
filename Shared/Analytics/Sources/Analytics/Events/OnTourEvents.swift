//
//  OnTourEvents.swift
//  Analytics
//
//  Structured analytics for the On Tour tab. These events carry no artist
//  identity — only facet names, counts, and tab/sheet lifecycle — per the
//  On Tour privacy invariant (taste/interest data never leaves the device).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - On Tour tab

/// Event fired once per launch, the first time the On Tour tab is opened. The
/// view latches on first appearance, so switching away and back does not re-fire.
@AnalyticsEvent
public struct OnTourTabViewed {
    public init() {}
}

/// Event fired when the filter sheet is opened.
@AnalyticsEvent
public struct OnTourFilterSheetOpened {
    public init() {}
}

/// Event fired on an explicit user filter action — changing a facet, clearing a
/// facet pill, or resetting. `facet` is the changed facet's key ("date", "venue",
/// "free", "all_ages", "genre") or "reset" for a full clear; `activeCount` is the
/// resulting number of engaged facet groups. Never carries any concert or artist data.
@AnalyticsEvent
public struct OnTourFilterApplied {
    public let facet: String
    public let activeCount: Int

    public init(facet: String, activeCount: Int) {
        self.facet = facet
        self.activeCount = activeCount
    }
}

/// Event fired when an active filter narrows the window to zero shows.
@AnalyticsEvent
public struct OnTourFilteredToZero {
    public init() {}
}

// MARK: - For You shelf (#493)

/// Event fired once per launch, the first time the For You recommendation shelf
/// renders with at least one card. `lovedCount` / `similarCount` / `stationCount`
/// are the per-tier sizes at that first render — volume without identity, per the
/// On Tour privacy invariant. `stationCount` is the cold-start station-affinity
/// tier (#551), broken out so it is never folded into `similarCount`. Never
/// carries a concert or artist id: which artists the listener likes stays on the
/// device.
@AnalyticsEvent
public struct ForYouShelfImpression {
    public let lovedCount: Int
    public let similarCount: Int
    public let stationCount: Int

    public init(lovedCount: Int, similarCount: Int, stationCount: Int) {
        self.lovedCount = lovedCount
        self.similarCount = similarCount
        self.stationCount = stationCount
    }
}

/// Event fired when a For You card is tapped through to the concert detail.
/// `tier` is "loved", "similar", or "station" — the recommendation kind only,
/// never the concert or the liked artist that surfaced it.
@AnalyticsEvent
public struct ForYouCardTapped {
    public let tier: String

    public init(tier: String) {
        self.tier = tier
    }
}

/// Event fired when the listener dismisses a For You card via its "Not interested"
/// menu. `tier` is "loved", "similar", or "station" — the recommendation kind
/// only, never the concert or the liked artist that surfaced it.
@AnalyticsEvent
public struct ForYouCardDismissed {
    public let tier: String

    public init(tier: String) {
        self.tier = tier
    }
}
