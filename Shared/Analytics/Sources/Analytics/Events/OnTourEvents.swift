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

/// Event fired once per launch, the first time the "Heard on WXYC" recommendation
/// shelf renders with at least one card. `lovedCount` / `stationCount` are the
/// per-tier sizes at that first render — volume without identity, per the On Tour
/// privacy invariant. `stationCount` is the cold-start station-recommended tier
/// (#577). Never carries a concert or artist id: which artists the listener likes
/// stays on the device.
@AnalyticsEvent
public struct ForYouShelfImpression {
    public let lovedCount: Int
    public let stationCount: Int

    public init(lovedCount: Int, stationCount: Int) {
        self.lovedCount = lovedCount
        self.stationCount = stationCount
    }
}

/// Event fired when a For You card is tapped through to the concert detail.
/// `tier` is "loved" or "station" — the recommendation kind only, never the
/// concert or the liked artist that surfaced it.
@AnalyticsEvent
public struct ForYouCardTapped {
    public let tier: String

    public init(tier: String) {
        self.tier = tier
    }
}

/// Event fired when the listener dismisses a For You card via its "Not interested"
/// menu. `tier` is "loved" or "station" — the recommendation kind only, never the
/// concert or the liked artist that surfaced it.
@AnalyticsEvent
public struct ForYouCardDismissed {
    public let tier: String

    public init(tier: String) {
        self.tier = tier
    }
}

// MARK: - Sharing (#536)

/// Event fired when the listener starts sharing a concert — invoking the detail
/// view's share button or the row's "Share Show" context action. `surface` is the
/// originating affordance ("detail" or "row") and is the event's only property:
/// the shared link resolves the show server-side, so no concert or artist id ever
/// rides along, per the On Tour privacy invariant.
@AnalyticsEvent
public struct ConcertShareInitiated {
    public let surface: String

    public init(surface: String) {
        self.surface = surface
    }
}

/// Event fired when a shared show link opens the app and the arrival path
/// finishes resolving it (#537). `source` is the link form — "universalLink"
/// (`wxyc.org/shows/<id>`, a friend tapped a public link) or "scheme"
/// (`wxyc://concert/<id>`, an app-owned surface). `resolution` is the ladder rung
/// that resolved it — "window" (already in the loaded list), "byID" (fetched
/// individually), or "missed" (couldn't be found). Both are low-cardinality
/// labels; the concert id never rides along — which show a listener opened is
/// taste data that stays on the device, per the On Tour privacy invariant.
@AnalyticsEvent
public struct ConcertDeepLinkOpened {
    public let source: String
    public let resolution: String

    public init(source: String, resolution: String) {
        self.source = source
        self.resolution = resolution
    }
}

// MARK: - Add to Calendar (#538)

/// Event fired when the listener commits an "Add to Calendar" — i.e. the
/// EventKit editor reports a saved event, not merely on tapping the affordance.
/// `surface` is the originating affordance ("detail" or "row"); `timing` is the
/// event shape the concert produced — "timed" (a known start instant) or
/// "allDay" (date-only or doors-only). Both are low-cardinality labels: no
/// concert, artist, or calendar identity ever rides along, per the On Tour
/// privacy invariant.
@AnalyticsEvent
public struct ConcertCalendarAdded {
    public let surface: String
    public let timing: String

    public init(surface: String, timing: String) {
        self.surface = surface
        self.timing = timing
    }
}
