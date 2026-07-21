//
//  MarketingRouteTests.swift
//  WXYC
//
//  Verifies the `-marketing` recording's route→tab mapping. `MarketingRoute` is
//  written by `MarketingModeController` during a `-marketing` run and mapped to
//  `RootTabView`'s private `Page` type — the same pattern `pendingConcertLink`
//  uses to drive the On Tour tab from outside the view.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@Suite("MarketingRoute → Page mapping")
struct MarketingRouteTests {
    @Test("Each marketing route maps to its tab page", arguments: [
        (MarketingRoute.nowPlaying, RootTabView.Page.playlist),
        (MarketingRoute.onTour, RootTabView.Page.onTour),
        (MarketingRoute.liked, RootTabView.Page.liked),
        (MarketingRoute.station, RootTabView.Page.station),
    ])
    func mapsToPage(route: MarketingRoute, expected: RootTabView.Page) {
        #expect(RootTabView.Page.page(for: route) == expected)
    }
}
