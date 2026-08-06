//
//  OpenVenue.swift
//  Intents
//
//  Foregrounds the app on a venue's shows (OT-C4). Because the intent runs
//  in-app once `openAppWhenRun` foregrounds it, `perform()` posts the typed
//  `VenueOpenMessage` directly rather than round-tripping through a
//  `wxyc://` URL scheme — a venue has no public share URL, and this mirrors
//  `OpenConcert`'s own precedent for the same reason. The existing
//  `Singletonia` -> `PendingVenueLink` -> `OnTourTabView` observer hop
//  narrows the On Tour tab's venue filter to just this venue's shows.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation

public struct OpenVenue: AppIntent, OpenIntent {
    public static let title: LocalizedStringResource = "Open Venue"
    public static let description = IntentDescription("Opens a venue's WXYC On Tour shows in the app.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Venue")
    public var target: VenueEntity

    public init() { }

    public init(target: VenueEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        // `target.id` bridges back to the backend's `Int` id space that
        // `VenueOpenMessage` speaks (see `EntityID.venueID`). Every
        // `VenueEntity` this app constructs already satisfies the bridge, so
        // this guard only covers a value that can't arise in practice rather
        // than crashing on a force-unwrap.
        if let venueID = target.id.venueID {
            postOpenMessage(VenueOpenMessage(venueID: venueID))
        }
        return .result()
    }
}
