//
//  TouringEvents.swift
//  Analytics
//
//  Structured analytics for the Touring Soon tab. These events carry no artist
//  identity — only facet names, counts, and tab/sheet lifecycle — per the
//  Touring Soon privacy invariant (taste/interest data never leaves the device).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - Touring Soon tab

/// Event fired once per launch, the first time the Touring tab is opened. The
/// view latches on first appearance, so switching away and back does not re-fire.
@AnalyticsEvent
public struct TouringTabViewed {
    public init() {}
}

/// Event fired when the filter sheet is opened.
@AnalyticsEvent
public struct TouringFilterSheetOpened {
    public init() {}
}

/// Event fired on an explicit user filter action — changing a facet, clearing a
/// facet pill, or resetting. `facet` is the changed facet's key ("date", "venue",
/// "free", "all_ages") or "reset" for a full clear; `activeCount` is the resulting
/// number of engaged facet groups. Never carries any concert or artist data.
@AnalyticsEvent
public struct TouringFilterApplied {
    public let facet: String
    public let activeCount: Int

    public init(facet: String, activeCount: Int) {
        self.facet = facet
        self.activeCount = activeCount
    }
}

/// Event fired when an active filter narrows the window to zero shows.
@AnalyticsEvent
public struct TouringFilteredToZero {
    public init() {}
}
