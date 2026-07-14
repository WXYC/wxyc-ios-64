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

/// Event fired when the Touring tab's list is first shown for a session.
@AnalyticsEvent
public struct TouringTabViewed {
    public init() {}
}

/// Event fired when the filter sheet is opened.
@AnalyticsEvent
public struct TouringFilterSheetOpened {
    public init() {}
}

/// Event fired when a single facet is changed. Carries the facet name and the
/// resulting number of engaged facet groups — never any concert or artist data.
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
