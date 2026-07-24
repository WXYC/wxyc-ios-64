//
//  TouringDateWindow.swift
//  Intents
//
//  The Siri-facing date window for `ToursNearMe` (OT-C2,
//  WXYC/wxyc-ios-64#625): tonight / this weekend / next 7 days, bridging to
//  the same `ConcertFilterState.DateWindow` the On Tour tab's filter sheet
//  already evaluates. Deliberately omits `.all` -- an unbounded "touring near
//  me" answer isn't the marquee query this intent answers, and every
//  `ConcertFilterState` window is a superset of `.tonight`, so a broader
//  answer is always just a re-ask with a different case.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Concerts

/// The date window a listener can pick when asking Siri/Spotlight what's
/// touring near them. A thin, Siri-displayable wrapper around
/// `ConcertFilterState.DateWindow` -- kept as its own `AppEnum` rather than
/// making the domain type itself conform, so `Concerts` (pure domain) never
/// has to import `AppIntents`.
public enum TouringDateWindow: String, AppEnum {
    case tonight
    case thisWeekend
    case next7Days

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Date Window"

    public static let caseDisplayRepresentations: [TouringDateWindow: DisplayRepresentation] = [
        .tonight: "Tonight",
        .thisWeekend: "This Weekend",
        .next7Days: "Next 7 Days",
    ]

    /// Bridges to the domain-level window `ToursNearMeQuery.matchingConcerts`
    /// (and the On Tour tab's own filter sheet) actually evaluates.
    public var filterWindow: ConcertFilterState.DateWindow {
        switch self {
        case .tonight: .tonight
        case .thisWeekend: .thisWeekend
        case .next7Days: .next7Days
        }
    }
}
