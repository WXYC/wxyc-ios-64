//
//  PendingVenueLink.swift
//  WXYC
//
//  The app's "an OpenVenue intent asked to see a venue's shows" state
//  (OT-C4). `OpenVenue.perform()` posts a typed `VenueOpenMessage`;
//  `Singletonia` catches it and stashes this value, which `RootTabView`
//  reacts to (flipping to the On Tour tab) and `OnTourTabView` consumes
//  (narrowing the venue filter to just this venue), mirroring
//  `PendingConcertLink` (#537).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A pending request to filter the On Tour tab down to one venue's shows.
struct PendingVenueLink: Equatable, Sendable {
    /// The venue id from the `OpenVenue` intent.
    let id: Int
}
