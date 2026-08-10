//
//  MarketingRouteTests.swift
//  WXYC
//
//  Verifies the `-marketing` recording's route→section mapping. `MarketingRoute`
//  is written by `MarketingModeController` during a `-marketing` run and mapped to
//  an `AppSection` — the same pattern `pendingConcertLink` uses to drive the On
//  Tour tab from outside the view.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@Suite("MarketingRoute → AppSection mapping")
struct MarketingRouteTests {
    @Test("Each marketing route maps to its section", arguments: [
        (MarketingRoute.nowPlaying, AppSection.playlist),
        (MarketingRoute.onTour, AppSection.onTour),
        (MarketingRoute.liked, AppSection.liked),
        (MarketingRoute.station, AppSection.station),
    ])
    func mapsToSection(route: MarketingRoute, expected: AppSection) {
        #expect(route.section == expected)
    }
}
